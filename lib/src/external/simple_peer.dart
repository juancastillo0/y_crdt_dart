/*! simple-peer. MIT License. Feross Aboukhadijeh <https://feross.org/opensource> */
// const debug = require("debug")("simple-peer");
// const getBrowserRTC = require("get-browser-rtc");
// const randombytes = require("randombytes");
// const stream = require("readable-stream");
// const queueMicrotask = require("queue-microtask"); // TODO: remove when Node 10 is not supported
// const errCode = require("err-code");
// const { Buffer } = require("buffer");

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';
import 'package:y_crdt/src/external/simple_peer_event.dart';
import 'package:y_crdt/src/lib0/prng.dart' as prng;
import 'package:y_crdt/src/y_crdt_base.dart';

export 'package:flutter_webrtc/flutter_webrtc.dart' show RTCDataChannelMessage;

// commit: d1c0ebe13233afb8d4eceafd2cbdd4000ffebea1

const MAX_BUFFERED_AMOUNT = 64 * 1024;
const ICECOMPLETE_TIMEOUT = 5 * 1000;
const CHANNEL_CLOSING_TIMEOUT = 5 * 1000;

final _log = Logger();

/**
 * WebRTC peer connection. Same API as node core `net.Socket`, plus a few extra methods.
 * Duplex stream.
 * @param {Object} opts
 */

final _random = Random();

class PeerOptions {
  static String _defaultSdpTransform(String sdp) => sdp;

  const PeerOptions({
    this.initiator = false,
    this.channelConfig,
    this.channelName,
    this.config = const {
      "iceServers": [
        {"urls": 'stun:stun.l.google.com:19302'},
        {"urls": 'stun:global.stun.twilio.com:3478?transport=udp'}
      ]
    },
    this.offerOptions = const {},
    this.answerOptions = const {},
    this.sdpTransform = PeerOptions._defaultSdpTransform,
    this.streams = const [],
    this.trickle = true,
    this.allowHalfTrickle = false,
    this.objectMode = false,
    this.iceCompleteTimeout = ICECOMPLETE_TIMEOUT,
  });

  final bool initiator; //: false
  final RTCDataChannelInit? channelConfig; //: {}
  final String? channelName; //: '<random string>'
  final Map<String, Object?> config; //:
  final Map<String, Object?> offerOptions; //: {}
  final Map<String, Object?> answerOptions; //: {}
  final String Function(String sdp)
      sdpTransform; //: function (sdp) { return sdp; }
  final List<MediaStream> streams; //: []
  final bool trickle; //: true
  final bool allowHalfTrickle; //: false
  // final bool wrtc: {}, // RTCPeerConnection/RTCSessionDescription/RTCIceCandidat
  final bool objectMode; //: false
  final int iceCompleteTimeout;

  PeerOptions copyWith({
    bool? initiator,
    RTCDataChannelInit? channelConfig,
    String? channelName,
    Map<String, Object?>? config,
    Map<String, Object?>? offerOptions,
    Map<String, Object?>? answerOptions,
    String Function(String sdp)? sdpTransform,
    List<MediaStream>? streams,
    bool? trickle,
    bool? allowHalfTrickle,
    bool? objectMode,
    int? iceCompleteTimeout,
  }) {
    return PeerOptions(
      initiator: initiator ?? this.initiator,
      channelConfig: channelConfig ?? this.channelConfig,
      channelName: channelName ?? this.channelName,
      config: config ?? this.config,
      offerOptions: offerOptions ?? this.offerOptions,
      answerOptions: answerOptions ?? this.answerOptions,
      sdpTransform: sdpTransform ?? this.sdpTransform,
      streams: streams ?? this.streams,
      trickle: trickle ?? this.trickle,
      allowHalfTrickle: allowHalfTrickle ?? this.allowHalfTrickle,
      objectMode: objectMode ?? this.objectMode,
      iceCompleteTimeout: iceCompleteTimeout ?? this.iceCompleteTimeout,
    );
  }

  @override
  String toString() {
    return 'PeerOptions(initiator: $initiator, channelName: $channelName, config: $config, '
        'channelConfig: $channelConfig, offerOptions: $offerOptions, answerOptions: $answerOptions, '
        'streams: $streams, trickle: $trickle, allowHalfTrickle: $allowHalfTrickle, objectMode: $objectMode, '
        'iceCompleteTimeout: $iceCompleteTimeout)';
  }
}

class Peer {
  final _id = prng.word(_random, 7, 7);

  Stream<SimplePeerEvent> get eventStream => _eventStreamController.stream;
  final _eventStreamController = StreamController<SimplePeerEvent>.broadcast();

  Stream<RTCDataChannelMessage> get messageStream =>
      _messageStreamController.stream;
  final _messageStreamController =
      StreamController<RTCDataChannelMessage>.broadcast();

  void emit(SimplePeerEvent event) {
    this._eventStreamController.add(event);
  }

  late final RTCPeerConnection _pc;

  final _pcReadyCompleter = Completer<void>();
  Future<void> get pcReadyFutute => _pcReadyCompleter.future;
  bool _pcReady = false;
  bool _channelReady = false;
  bool _iceComplete = false; // ice candidate trickle done (got null candidate)
  Timer? _iceCompleteTimer; // send an offer/answer anyway after some timeout
  RTCDataChannel? _channel;
  final _pendingCandidates = <RTCIceCandidate>[];

  bool _isNegotiating =
      false; // is this peer waiting for negotiation to complete?
  bool _firstNegotiation = true;
  bool _batchedNegotiation = false; // batch synchronous negotiations
  bool _queuedNegotiation = false; // is there a queued negotiation request?
  final _sendersAwaitingStable = <RTCRtpSenderWithDelete>[];
  final _senderMap =
      <MediaStreamTrack, Map<MediaStream, RTCRtpSenderWithDelete>>{};
  Timer? _closingInterval;

  final _remoteTracks = <MediaStreamTrack>[];
  final _remoteStreams = <MediaStream>[];

  Uint8List? _chunk;
  void Function(Object?)? _cb;
  Timer? _interval;
  bool _connecting = false;

  final String? channelName;

  bool get initiator => opts.initiator;

  final PeerOptions opts;
  late final RTCDataChannelInit channelConfig;
  final Map<String, Object?> config;
  // offerOptions = opts.offerOptions || {};
  // answerOptions = opts.answerOptions || {};
  // sdpTransform = opts.sdpTransform || ((sdp) => sdp);
  // final List<MediaStream> streams; // support old "stream" option
  // trickle = opts.trickle != undefined ? opts.trickle : true;
  // allowHalfTrickle =
  //   opts.allowHalfTrickle != undefined ? opts.allowHalfTrickle : false;
  // this.iceCompleteTimeout = opts.iceCompleteTimeout || ICECOMPLETE_TIMEOUT;

  bool destroyed = false;
  bool destroying = false;
  bool _connected = false;

  String? remoteAddress;
  String? remoteFamily; // "IPv6" : "IPv4"
  int? remotePort;
  String? localAddress;
  String? localFamily; // "IPv6" : "IPv4"
  int? localPort;
  StreamSubscription<SimplePeerEvent>? _onFinishSubscription;
  final _requestedTransceivers = <RTCRtpTransceiver>{};

  Peer(this.opts)
      : channelName = opts.initiator
            ? (opts.channelName ??
                prng.word(_random, 7, 7)) // randombytes(20).toString("hex")
            : null,
        config = {...Peer.defaultConfig, ...opts.config} {
    this.channelConfig = opts.channelConfig ?? Peer.defaultChannelConfig;
    // opts =
    //   {
    //     "allowHalfOpen": false,
    //     ...opts
    //   };
    this._debug("new peer %o $opts");

    // this._wrtc =
    //   opts.wrtc && typeof opts.wrtc == "object" ? opts.wrtc : getBrowserRTC();

    // if (!this._wrtc) {
    //   if (typeof window == "undefined") {
    //     throw errCode(
    //       Exception(
    //         "No WebRTC support: Specify `opts.wrtc` option in this environment"
    //       ),
    //       "ERR_WEBRTC_SUPPORT"
    //     );
    //   } else {
    //     throw errCode(
    //       Exception("No WebRTC support: Not a supported browser"),
    //       "ERR_WEBRTC_SUPPORT"
    //     );
    //   }
    // }

    createPeerConnection(this.config).then(this._setupPc).onError((err, s) {
      this.destroy(errCode(err, "ERR_PC_CONSTRUCTOR", s));
    });
  }

  void _setupPc(RTCPeerConnection pc) {
    this._pc = pc;
    // We prefer feature detection whenever possible, but sometimes that's not
    // possible for certain implementations.
    // TODO:
    // this._isReactNativeWebrtc = typeof this._pc._peerConnectionId == "number";

    pc.onIceConnectionState = (_) {
      this._debug(
        "onIceConnectionState (connection: $_)",
      );
      this._onIceStateChange();
    };
    pc.onIceGatheringState = (_) {
      this._debug(
        "onIceGatheringState (gathering: $_)",
      );
      this._onIceStateChange();
    };
    pc.onConnectionState = (_) {
      this._debug(
        "onConnectionState ($_)",
      );
      this._onConnectionStateChange();
    };
    pc.onSignalingState = (_) {
      this._debug(
        "onSignalingState ($_)",
      );
      this._onSignalingStateChange();
    };
    pc.onIceCandidate = (event) {
      this._debug(
        "onIceCandidate",
      );
      this._onIceCandidate(event);
    };

    // HACK: Fix for odd Firefox behavior, see: https://github.com/feross/simple-peer/pull/783
    // TODO:
    // if (typeof this._pc.peerIdentity === 'object') {
    //   this._pc.peerIdentity.catch(err => {
    //     this.destroy(errCode(err, 'ERR_PC_PEER_IDENTITY'))
    //   })
    // }

    // Other spec events, unused by this implementation:
    // - onconnectionstatechange
    // - onicecandidateerror
    // - onfingerprintfailure
    // - onnegotiationneeded

    if (this.initiator || this.channelConfig.negotiated) {
      pc
          .createDataChannel(
            this.channelName!,
            this.channelConfig,
          )
          .then(this._setupData);
    } else {
      pc.onDataChannel = this._setupData;
    }

    if (this.opts.streams.isNotEmpty) {
      this.opts.streams.forEach((stream) {
        this.addStream(stream);
      });
    }
    pc.onTrack = (event) {
      this._onTrack(event);
    };

    this._debug("initial negotiation");
    this._needsNegotiation();

    this._pcReadyCompleter.complete();
    // this._onFinishBound = () {
    //   this._onFinish();
    // };
    // TODO:
    // this._onFinishSubscription = this.once(
    //   (event) => event.maybeWhen(
    //     finish: () => true,
    //     orElse: () => false,
    //   ),
    //   this._onFinish,
    // );
  }

  StreamSubscription<SimplePeerEvent> once(
    bool Function(SimplePeerEvent event) predicate,
    void Function() callback,
  ) {
    StreamSubscription<SimplePeerEvent>? subs;
    subs = this.eventStream.listen((event) {
      if (predicate(event)) {
        callback();
        subs!.cancel();
      }
    });
    return subs;
  }

  int get bufferSize {
    // TODO:
    // this._channel?.bufferedAmount ??
    return 0;
  }

  // HACK: it's possible channel.readyState is "closing" before peer.destroy() fires
  // https://bugs.chromium.org/p/chromium/issues/detail?id=882743
  bool get connected {
    return this._connected &&
        this._channel?.state == RTCDataChannelState.RTCDataChannelOpen;
  }

  Map<String, dynamic> address() {
    return {
      "port": this.localPort,
      "family": this.localFamily,
      "address": this.localAddress,
    };
  }

  void signalString(String data) {
    Map<String, Object?> _data;
    try {
      _data = jsonDecode(data) as Map<String, Object?>;
    } catch (err) {
      _data = {};
    }
    this.signal(_data);
  }

  Future<void> signal(Map<String, Object?> _data) async {
    if (this._checkIsDestroying('signal')) return;
    this._debug("signal()");
    final data = SignalData.fromJson(_data);
    await this.pcReadyFutute;

    if (data.renegotiate != null && this.initiator) {
      this._debug("got request to renegotiate");
      this._needsNegotiation();
    }
    if (data.transceiverRequest != null && this.initiator) {
      this._debug("got request for transceiver");
      await this.addTransceiver(data.transceiverRequest!);
    }
    if (data.candidate != null) {
      final remoteDescription = await this._pc.getRemoteDescription();
      if (remoteDescription != null &&
          (remoteDescription.type?.isNotEmpty ?? false)) {
        await this._addIceCandidate(data.candidate!);
      } else {
        this._pendingCandidates.add(data.candidate!);
      }
    }
    if (data.sdp != null) {
      await this
          ._pc
          .setRemoteDescription(RTCSessionDescription(data.sdp, data.type))
          .then((_) async {
        if (this.destroyed) return;

        this._pendingCandidates.forEach((candidate) {
          this._addIceCandidate(candidate);
        });
        this._pendingCandidates.clear();
        final remoteDescription = await this._pc.getRemoteDescription();

        if (remoteDescription?.type == "offer") this._createAnswer();
      }).onError((err, s) {
        this.destroy(errCode(err, "ERR_SET_REMOTE_DESCRIPTION", s));
      });
    }
    if (data.sdp == null &&
        data.candidate == null &&
        data.renegotiate == null &&
        data.transceiverRequest == null) {
      this.destroy(errCode(
          Exception("signal() called with invalid signal data"),
          "ERR_SIGNALING"));
    }
  }

  Future<void> _addIceCandidate(RTCIceCandidate candidate) {
    return this._pc.addCandidate(candidate).onError((err, s) {
      // TODO:
      // if (
      // !iceCandidateObj.address ||
      // iceCandidateObj.address.endsWith(".local")
      // ) {
      // warn("Ignoring unsupported ICE candidate.");
      // } else {
      this.destroy(errCode(err, "ERR_ADD_ICE_CANDIDATE", s));
      // }
    });
  }

  /**
   * Send text/binary data to the remote peer.
   * @param {ArrayBufferView|ArrayBuffer|Buffer|string|Blob} chunk
   */
  Future<void> send(RTCDataChannelMessage message) async {
    if (this._checkIsDestroying('send')) return;
    return this._channel!.send(message);
    // if (chunk is String) {
    //   this._channel!.send(RTCDataChannelMessage(chunk));
    // } else if (chunk is Uint8List) {
    //   this._channel!.send(RTCDataChannelMessage.fromBinary(chunk));
    // }
  }

  Future<void> sendBinary(Uint8List message) {
    return this.send(RTCDataChannelMessage.fromBinary(message));
    // if (chunk is String) {
    //   this._channel!.send(RTCDataChannelMessage(chunk));
    // } else if (chunk is Uint8List) {
    //   this._channel!.send(RTCDataChannelMessage.fromBinary(chunk));
    // }
  }

  Future<void> sendString(String message) {
    return this.send(RTCDataChannelMessage(message));
    // if (chunk is String) {
    //   this._channel!.send(RTCDataChannelMessage(chunk));
    // } else if (chunk is Uint8List) {
    //   this._channel!.send(RTCDataChannelMessage.fromBinary(chunk));
    // }
  }

  /**
   * Add a Transceiver to the connection.
   * @param {String} kind
   * @param {Object} init
   */
  Future<void> addTransceiver(TransceiverRequest value) async {
    if (this._checkIsDestroying('addTransceiver')) return;
    this._debug("addTransceiver()");

    if (this.initiator) {
      try {
        await this._pc.addTransceiver(kind: value.kind, init: value.init);
        this._needsNegotiation();
      } catch (err, s) {
        this.destroy(errCode(err, "ERR_ADD_TRANSCEIVER", s));
      }
    } else {
      this.emit(SimplePeerEvent.signal({
        // request initiator to renegotiate
        "type": "transceiverRequest",
        "transceiverRequest": {"kind": value.kind, "init": value.init},
      }));
    }
  }

  /**
   * Add a MediaStream to the connection.
   * @param {MediaStream} stream
   */
  void addStream(MediaStream stream) {
    if (this._checkIsDestroying('addStream')) return;
    this._debug("addStream()");

    stream.getTracks().forEach((track) {
      this.addTrack(track, stream);
    });
  }

  /**
   * Add a MediaStreamTrack to the connection.
   * @param {MediaStreamTrack} track
   * @param {MediaStream} stream
   */
  void addTrack(MediaStreamTrack track, MediaStream stream) async {
    if (this._checkIsDestroying('addTrack')) return;
    this._debug("addTrack()");

    final submap = this._senderMap.get(track) ??
        {}; // nested Maps map [track, stream] to sender
    var sender = submap.get(stream);
    if (sender == null) {
      sender = RTCRtpSenderWithDelete(await this._pc.addTrack(track, stream));
      submap.set(stream, sender);
      this._senderMap.set(track, submap);
      this._needsNegotiation();
    } else if (sender.removed) {
      throw errCode(
          Exception(
              "Track has been removed. You should enable/disable tracks that you want to re-add."),
          "ERR_SENDER_REMOVED");
    } else {
      throw errCode(Exception("Track has already been added to that stream."),
          "ERR_SENDER_ALREADY_ADDED");
    }
  }

  /**
   * Replace a MediaStreamTrack by another in the connection.
   * @param {MediaStreamTrack} oldTrack
   * @param {MediaStreamTrack} newTrack
   * @param {MediaStream} stream
   */
  Future<void> replaceTrack(
    MediaStreamTrack oldTrack,
    MediaStreamTrack? newTrack,
    MediaStream stream,
  ) async {
    if (this._checkIsDestroying('replaceTrack')) return;
    this._debug("replaceTrack()");

    final submap = this._senderMap.get(oldTrack);
    final sender = submap?.get(stream);
    if (sender == null) {
      throw errCode(Exception("Cannot replace track that was never added."),
          "ERR_TRACK_NOT_ADDED");
    }
    if (newTrack != null) {
      this._senderMap.set(newTrack, submap!);
    }
    final _sender = sender.sender;

    // TODO:
    if (newTrack == null) {
      return;
    }
    try {
      await _sender.replaceTrack(newTrack);
    } catch (e, s) {
      this.destroy(errCode(
        Exception("replaceTrack is not supported in this browser. $e - $s"),
        "ERR_UNSUPPORTED_REPLACETRACK",
        s,
      ));
    }
  }

  /**
   * Remove a MediaStreamTrack from the connection.
   * @param {MediaStreamTrack} track
   * @param {MediaStream} stream
   */
  Future<void> removeTrack(MediaStreamTrack track, MediaStream stream) async {
    if (this._checkIsDestroying('removeTrack')) return;
    this._debug("removeSender()");

    final submap = this._senderMap.get(track);
    final sender = submap?.get(stream);
    if (sender == null) {
      throw errCode(Exception("Cannot remove track that was never added."),
          "ERR_TRACK_NOT_ADDED");
    }
    try {
      sender.removed = true;
      await this._pc.removeTrack(sender.sender);
    } catch (err, s) {
      String? name;
      try {
        name == (err as dynamic).name;
      } catch (_) {}
      if (name == "NS_ERROR_UNEXPECTED") {
        this._sendersAwaitingStable.add(
            sender); // HACK: Firefox must wait until (signalingState == stable) https://bugzilla.mozilla.org/show_bug.cgi?id=1133874
      } else {
        this.destroy(errCode(err, "ERR_REMOVE_TRACK", s));
      }
    }
    this._needsNegotiation();
  }

  /**
   * Remove a MediaStream from the connection.
   * @param {MediaStream} stream
   */
  void removeStream(MediaStream stream) {
    if (this._checkIsDestroying('removeStream')) return;
    this._debug("removeSenders()");

    stream.getTracks().forEach((track) {
      this.removeTrack(track, stream);
    });
  }

  void _needsNegotiation() {
    this._debug("_needsNegotiation");
    if (this._batchedNegotiation) return; // batch synchronous renegotiations
    this._batchedNegotiation = true;
    Future.delayed(Duration.zero, () {
      this._batchedNegotiation = false;
      if (this.initiator || !this._firstNegotiation) {
        this._debug("starting batched negotiation");
        this.negotiate();
      } else {
        this._debug("non-initiator initial negotiation request discarded");
      }
      this._firstNegotiation = false;
    });
  }

  void negotiate() {
    if (this._checkIsDestroying('negotiate')) return;
    if (this.initiator) {
      if (this._isNegotiating) {
        this._queuedNegotiation = true;
        this._debug("already negotiating, queueing");
      } else {
        this._debug("start negotiation");
        Future.delayed(Duration.zero, () {
          // HACK: Chrome crashes if we immediately call createOffer
          this._createOffer();
        });
      }
    } else {
      if (this._isNegotiating) {
        this._queuedNegotiation = true;
        this._debug("already negotiating, queueing");
      } else {
        this._debug("requesting negotiation from initiator");
        this.emit(SimplePeerEvent.signal({
          // request initiator to renegotiate
          "type": "renegotiate",
          "renegotiate": true,
        }));
      }
    }
    this._isNegotiating = true;
  }

  bool _checkIsDestroying(String funcName) {
    if (this.destroying) {
      return true;
    }
    if (this.destroyed) {
      throw errCode(
        Exception('cannot $funcName after peer is destroyed'),
        'ERR_DESTROYED',
      );
    }
    return false;
  }

  // TODO: Delete this method once readable-stream is updated to contain a default
  // implementation of destroy() that automatically calls _destroy()
  // See: https://github.com/nodejs/readable-stream/issues/283
  void destroy([Object? err]) {
    this._destroy(err, () {});
  }

  void _destroy(Object? err, void Function() cb) {
    if (this.destroyed || this.destroying) return;
    this.destroying = true;

    this._debug("destroying (error: $err)");

    Future.delayed(Duration.zero, () async {
      // allow events concurrent with the call to _destroy() to fire (see #692)
      this.destroyed = true;
      this.destroying = false;

      this._debug("destroy (error: $err)");

      // TODO:
      // this.readable = false;
      // this.writable = false;

      // if (!this._readableState.ended) this.push(null);
      // if (!this._writableState.finished) this.end();

      this._connected = false;
      this._pcReady = false;
      this._channelReady = false;
      this._remoteTracks.clear(); // this._remoteTracks = null;
      this._remoteStreams.clear(); // this._remoteStreams = null;
      this._senderMap.clear(); // this._senderMap = null;
      this._requestedTransceivers.clear();

      this._closingInterval?.cancel();
      this._closingInterval = null;

      this._interval?.cancel();
      this._interval = null;
      this._chunk = null;
      this._cb = null;

      // if (this._onFinishBound) {
      // this.removeListener("finish", this._onFinish);
      // }
      // this._onFinishBound = null;
      // ignore: unawaited_futures
      this._onFinishSubscription?.cancel();
      this._onFinishSubscription = null;

      if (this._channel != null) {
        final _channel = this._channel!;
        try {
          await _channel.close();
        } catch (_) {}

        // allow events concurrent with destruction to be handled
        _channel.onMessage = null;
        _channel.onDataChannelState = null;
      }
      if (this._pcReadyCompleter.isCompleted) {
        try {
          await this._pc.close();
        } catch (_) {}

        // allow events concurrent with destruction to be handled
        this._pc.onIceConnectionState = null;
        this._pc.onIceGatheringState = null;
        this._pc.onSignalingState = null;
        this._pc.onIceCandidate = null;
        this._pc.onTrack = null;
        this._pc.onDataChannel = null;
      }
      // this._pc = null;
      this._channel = null;

      if (err != null) this.emit(SimplePeerEvent.error(err));
      this.emit(const SimplePeerEvent.close());
      cb();
    });
  }

  void _setupData(RTCDataChannel channel) {
    // if (!channel) {
    //   // In some situations `pc.createDataChannel()` returns `undefined` (in wrtc),
    //   // which is invalid behavior. Handle it gracefully.
    //   // See: https://github.com/feross/simple-peer/issues/163
    //   return this.destroy(
    //     errCode(
    //       Exception("Data channel event is missing `channel` property"),
    //       "ERR_DATA_CHANNEL"
    //     )
    //   );
    // }

    this._channel = channel;
    // TODO:
    // channel.binaryType = "arraybuffer";

    // if (channel.bufferedAmountLowThreshold is num) {
    //   channel.bufferedAmountLowThreshold = MAX_BUFFERED_AMOUNT;
    // }

    // this.channelName = channel.label;

    // TODO:
    // channel.onMessage = this._onChannelMessage;
    this._messageStreamController.addStream(channel.messageStream);
    // channel.onbufferedamountlow = () {
    //   this._onChannelBufferedAmountLow();
    // };
    channel.onDataChannelState = (state) {
      switch (state) {
        case RTCDataChannelState.RTCDataChannelClosed:
          this._onChannelClose();
          break;
        case RTCDataChannelState.RTCDataChannelClosing:
          break;
        case RTCDataChannelState.RTCDataChannelConnecting:
          break;
        case RTCDataChannelState.RTCDataChannelOpen:
          this._onChannelOpen();
          break;
        default:
      }
    };
    // TODO:
    channel.messageStream.handleError((Object err, StackTrace s) {
      this.destroy(errCode(err, "ERR_DATA_CHANNEL", s));
      throw err;
    });

    // HACK: Chrome will sometimes get stuck in readyState "closing", let's check for this condition
    // https://bugs.chromium.org/p/chromium/issues/detail?id=882743
    bool isClosing = false;
    this._closingInterval = Timer.periodic(
      Duration(milliseconds: CHANNEL_CLOSING_TIMEOUT),
      (_) {
        // No "onclosing" event
        if (channel.state == RTCDataChannelState.RTCDataChannelClosing) {
          if (isClosing) {
            this._onChannelClose(); // closing timed out: equivalent to onclose firing
          }
          isClosing = true;
        } else {
          isClosing = false;
        }
      },
    );
  }

  // TODO:
  // void _read() {}

  // void _write(Uint8List chunk, _encoding, void Function(Object?) cb) {
  //   if (this.destroyed) {
  //     return cb(errCode(Exception("cannot write after peer is destroyed"),
  //         "ERR_DATA_CHANNEL"));
  //   }

  //   if (this._connected) {
  //     try {
  //       this.send(chunk);
  //     } catch (err) {
  //       return this.destroy(errCode(err, "ERR_DATA_CHANNEL"));
  //     }
  //     // if (this._channel.bufferedAmount > MAX_BUFFERED_AMOUNT) {
  //     //   this._debug(
  //     //     "start backpressure: bufferedAmount ${this._channel!.bufferedAmount}",
  //     //   );
  //     //   this._cb = cb;
  //     // } else {
  //     //   cb(null);
  //     // }
  //     cb(null);
  //   } else {
  //     this._debug("write before connect");
  //     this._chunk = chunk;
  //     this._cb = cb;
  //   }
  // }

  // When stream finishes writing, close socket. Half open connections are not
  // supported.
  // TODO:
  // void _onFinish() {
  //   if (this.destroyed) return;

  //   // Wait a bit before destroying so the socket flushes.
  //   // TODO: is there a more reliable way to accomplish this?
  //   final destroySoon = () {
  //     Future.delayed(const Duration(seconds: 1), () => this.destroy());
  //   };

  //   if (this._connected) {
  //     destroySoon();
  //   } else {
  //     this.once(
  //       (event) => event.maybeWhen(
  //         connect: () => true,
  //         orElse: () => false,
  //       ),
  //       destroySoon,
  //     );
  //   }
  // }

  void _startIceCompleteTimeout() {
    if (this.destroyed) return;
    if (this._iceCompleteTimer != null) return;
    this._debug("started iceComplete timeout");
    this._iceCompleteTimer = Timer.periodic(
        Duration(milliseconds: this.opts.iceCompleteTimeout), (_) {
      if (!this._iceComplete) {
        this._iceComplete = true;
        this._debug("iceComplete timeout completed");
        this.emit(const SimplePeerEvent.iceTimeout());
        this.emit(const SimplePeerEvent.iceComplete());
      }
    });
  }

  void _createOffer() {
    if (this.destroyed) return;

    this._pc.createOffer(this.opts.offerOptions).then((offer) {
      if (this.destroyed) return;
      if (!this.opts.trickle && !this.opts.allowHalfTrickle) {
        offer.sdp = filterTrickle(offer.sdp!);
      }
      offer.sdp = this.opts.sdpTransform(offer.sdp!);

      final sendOffer = () async {
        if (this.destroyed) return;
        final localDescription = await this._pc.getLocalDescription();
        final signal = localDescription ?? offer;
        this._debug("signal");
        this.emit(SimplePeerEvent.signal({
          "type": signal.type,
          "sdp": signal.sdp,
        }));
      };

      final onSuccess = (_) {
        this._debug("createOffer success");
        if (this.destroyed) {
          return;
        }
        if (this.opts.trickle || this._iceComplete) {
          sendOffer();
        } else {
          this.once(
            (event) => event.maybeWhen(
              iceComplete: () => true,
              orElse: () => false,
            ),
            sendOffer,
          ); // wait for candidates
        }
      };

      final onError = (Object err, StackTrace s) {
        this.destroy(errCode(err, "ERR_SET_LOCAL_DESCRIPTION", s));
      };

      this._pc.setLocalDescription(offer).then(onSuccess).onError(onError);
    }).onError((err, s) {
      this.destroy(errCode(err, "ERR_CREATE_OFFER", s));
    });
  }

  void _requestMissingTransceivers() async {
    try {
      final transceivers = await this._pc.getTransceivers();
      transceivers.forEach((transceiver) {
        if (transceiver.mid == null &&
            transceiver.sender.track != null &&
            !this._requestedTransceivers.contains(transceiver)) {
          // HACK: Safari returns negotiated transceivers with a null mid
          _requestedTransceivers.add(transceiver);
          this.addTransceiver(TransceiverRequest(
            kind: typeStringToRTCRtpMediaType[transceiver.sender.track!.kind]!,
            init: RTCRtpTransceiverInit(),
          ));
        }
      });
    } catch (e, s) {
      print("_requestMissingTransceivers error $e\n$s");
    }
  }

  void _createAnswer() {
    if (this.destroyed) return;

    this._pc.createAnswer(this.opts.answerOptions).then((answer) {
      if (this.destroyed) return;
      if (!this.opts.trickle && !this.opts.allowHalfTrickle) {
        answer.sdp = filterTrickle(answer.sdp!);
      }
      answer.sdp = this.opts.sdpTransform(answer.sdp!);

      final sendAnswer = () async {
        if (this.destroyed) return;
        final signal = await this._pc.getLocalDescription() ?? answer;
        this._debug("signal");
        this.emit(SimplePeerEvent.signal({
          "type": signal.type,
          "sdp": signal.sdp,
        }));
        if (!this.initiator) this._requestMissingTransceivers();
      };

      final onSuccess = (_) {
        if (this.destroyed) {
          return;
        }
        if (this.opts.trickle || this._iceComplete) {
          sendAnswer();
        } else {
          this.once(
            (event) => event.maybeWhen(
              iceComplete: () => true,
              orElse: () => false,
            ),
            sendAnswer,
          );
        }
      };

      final onError = (Object err, StackTrace s) {
        this.destroy(errCode(err, "ERR_SET_LOCAL_DESCRIPTION", s));
      };

      this._pc.setLocalDescription(answer).then(onSuccess).onError(onError);
    }).onError((Object err, StackTrace s) {
      this.destroy(errCode(err, "ERR_CREATE_ANSWER", s));
    });
  }

  void _onConnectionStateChange() {
    if (this.destroyed) return;
    if (this._pc.connectionState ==
        RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
      this.destroy(
          errCode(Exception("Connection failed."), "ERR_CONNECTION_FAILURE"));
    }
  }

  void _onIceStateChange() {
    if (this.destroyed) return;
    final iceConnectionState = this._pc.iceConnectionState;
    final iceGatheringState = this._pc.iceGatheringState;

    this._debug(
      "iceStateChange (connection: $iceConnectionState) (gathering: $iceGatheringState)",
    );
    this.emit(SimplePeerEvent.iceStateChange(
      iceConnectionState: iceConnectionState,
      iceGatheringState: iceGatheringState,
    ));

    if (iceConnectionState ==
            RTCIceConnectionState.RTCIceConnectionStateConnected ||
        iceConnectionState ==
            RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      this._pcReady = true;
      this._maybeReady();
    }
    if (iceConnectionState ==
        RTCIceConnectionState.RTCIceConnectionStateFailed) {
      this.destroy(errCode(
          Exception("Ice connection failed."), "ERR_ICE_CONNECTION_FAILURE"));
    }
    if (iceConnectionState ==
        RTCIceConnectionState.RTCIceConnectionStateClosed) {
      this.destroy(errCode(
          Exception("Ice connection closed."), "ERR_ICE_CONNECTION_CLOSED"));
    }
  }

  void getStats(void Function(Object? err, List<StatsReport> stats) cb) async {
    try {
      final stats = await this._pc.getStats();
      cb(null, stats);
    } catch (err) {
      cb(err, []);
    }
    // // statreports can come with a value array instead of properties
    // final flattenValues = (report) {
    //   if (report.values is List) {
    //     report.values.forEach((value) {
    //       Object.assign(report, value);
    //     });
    //   }
    //   return report;
    // };

    // // Promise-based getStats() (standard)
    // if (this._pc.getStats.length == 0 || this._isReactNativeWebrtc) {
    //   this._pc.getStats().then(
    //     (res) {
    //       final reports = [];
    //       res.forEach((report) {
    //         reports.push(flattenValues(report));
    //       });
    //       cb(null, reports);
    //     },
    //     (err) => cb(err)
    //   );

    //   // Single-parameter callback-based getStats() (non-standard)
    // } else if (this._pc.getStats.length > 0) {
    //   this._pc.getStats(
    //     (res) {
    //       // If we destroy connection in `connect` callback this code might happen to run when actual connection is already closed
    //       if (this.destroyed) return;

    //       final reports = [];
    //       res.result().forEach((result) {
    //         final report = {};
    //         result.names().forEach((name) {
    //           report[name] = result.stat(name);
    //         });
    //         report.id = result.id;
    //         report.type = result.type;
    //         report.timestamp = result.timestamp;
    //         reports.push(flattenValues(report));
    //       });
    //       cb(null, reports);
    //     },
    //     (err) => cb(err)
    //   );

    //   // Unknown browser, skip getStats() since it's anyone's guess which style of
    //   // getStats() they implement.
    // } else {
    //   cb(null, []);
    // }
  }

  void _maybeReady() {
    this._debug(
      "maybeReady pc ${this._pcReady} channel ${this._channelReady}",
    );
    if (this._connected ||
        this._connecting ||
        !this._pcReady ||
        !this._channelReady) {
      return;
    }

    this._connecting = true;

    // HACK: We can't rely on order here, for details see https://github.com/js-platform/node-webrtc/issues/339
    void findCandidatePair() {
      if (this.destroyed) return;

      this.getStats((err, items) async {
        if (this.destroyed) return;

        // Treat getStats error as non-fatal. It's not essential.
        if (err != null) items = [];

        final remoteCandidates = <String, StatsReport>{};
        final localCandidates = <String, StatsReport>{};
        final candidatePairs = <String, StatsReport>{};
        bool foundSelectedCandidatePair = false;

        int? _getPort(Object? port) {
          final _port = port ?? "";
          return _port is num ? _port.toInt() : int.tryParse(_port as String);
        }

        items.forEach((item) {
          // TODO: Once all browsers support the hyphenated stats report types, remove
          // the non-hypenated ones
          if (item.type == "remotecandidate" ||
              item.type == "remote-candidate") {
            remoteCandidates[item.id] = item;
          }
          if (item.type == "localcandidate" || item.type == "local-candidate") {
            localCandidates[item.id] = item;
          }
          if (item.type == "candidatepair" || item.type == "candidate-pair") {
            candidatePairs[item.id] = item;
          }
        });

        final setSelectedCandidatePair = (StatsReport selectedCandidatePair) {
          foundSelectedCandidatePair = true;
          final local =
              localCandidates[selectedCandidatePair.values["localCandidateId"]];

          if (local != null &&
              (local.values.containsKey("ip") ||
                  local.values.containsKey("address"))) {
            // Spec
            this.localAddress =
                (local.values["ip"] ?? local.values["address"]) as String;
            this.localPort = _getPort(local.values["port"]);
          } else if (local != null && local.values.containsKey("ipAddreass")) {
            // Firefox
            this.localAddress = local.values["ipAddress"] as String;
            this.localPort = _getPort(local.values["portNumber"]);
          } else if (selectedCandidatePair.values["googLocalAddress"]
              is String) {
            // TODO: remove this once Chrome 58 is released
            final _address =
                (selectedCandidatePair.values["googLocalAddress"] as String)
                    .split(":");
            this.localAddress = _address[0];
            this.localPort = int.tryParse(_address[1]);
          }
          if (this.localAddress != null) {
            this.localFamily =
                this.localAddress!.contains(":") ? "IPv6" : "IPv4";
          }

          final remote = remoteCandidates[
              selectedCandidatePair.values["remoteCandidateId"]];

          if (remote != null &&
              (remote.values.containsKey("ip") ||
                  remote.values.containsKey("address"))) {
            // Spec
            this.remoteAddress =
                (remote.values["ip"] ?? remote.values["address"]) as String;
            this.remotePort = _getPort(remote.values["port"]);
          } else if (remote != null && remote.values.containsKey("ipAddress")) {
            // Firefox
            this.remoteAddress = remote.values["ipAddress"] as String;
            this.remotePort = _getPort(remote.values["portNumber"]);
          } else if (selectedCandidatePair.values["googRemoteAddress"]
              is String) {
            // TODO: remove this once Chrome 58 is released
            final _address =
                (selectedCandidatePair.values["googRemoteAddress"] as String)
                    .split(":");
            this.remoteAddress = _address[0];
            this.remotePort = int.tryParse(_address[1]);
          }
          if (this.remoteAddress != null) {
            this.remoteFamily =
                this.remoteAddress!.contains(":") ? "IPv6" : "IPv4";
          }

          this._debug(
            "connect local: ${this.localAddress}:${this.localPort} remote: ${this.remoteAddress}:%s",
          );
        };

        items.forEach((item) {
          // Spec-compliant
          if (item.type == "transport" &&
              item.values["selectedCandidatePairId"] is String) {
            setSelectedCandidatePair(candidatePairs[
                item.values["selectedCandidatePairId"] as String]!);
          }

          // Old implementations
          if ((item.type == "googCandidatePair" &&
                  item.values["googActiveConnection"] == "true") ||
              ((item.type == "candidatepair" ||
                      item.type == "candidate-pair") &&
                  item.values["selected"] == true)) {
            setSelectedCandidatePair(item);
          }
        });

        // Ignore candidate pair selection in browsers like Safari 11 that do not have any local or remote candidates
        // But wait until at least 1 candidate pair is available
        if (!foundSelectedCandidatePair &&
            (candidatePairs.isEmpty || localCandidates.isNotEmpty)) {
          Future.delayed(Duration(milliseconds: 100), findCandidatePair);
          return;
        } else {
          this._connecting = false;
          this._connected = true;
        }

        if (this._chunk != null) {
          try {
            await this.send(RTCDataChannelMessage.fromBinary(this._chunk!));
          } catch (err, s) {
            return this.destroy(errCode(err, "ERR_DATA_CHANNEL", s));
          }
          this._chunk = null;
          this._debug('sent chunk from "write before connect"');

          final cb = this._cb!;
          this._cb = null;
          cb(null);
        }

        // If `bufferedAmountLowThreshold` and 'onbufferedamountlow' are unsupported,
        // fallback to using setInterval to implement backpressure.
        // if (this._channel!.bufferedAmountLowThreshold is! num) {
        //   this._interval = Timer.periodic(Duration(milliseconds: 150), (_) => this._onInterval());
        //   if (this._interval.unref) this._interval.unref();
        // }

        this._debug("connect");
        this.emit(const SimplePeerEvent.connect());
      });
    }

    findCandidatePair();
  }

  void _onInterval() {
    if (this._cb == null || this._channel == null
        // || (this._channel!.bufferedAmount ?? 0) > MAX_BUFFERED_AMOUNT
        ) {
      return;
    }
    this._onChannelBufferedAmountLow();
  }

  void _onSignalingStateChange() {
    if (this.destroyed) return;

    if (this._pc.signalingState == RTCSignalingState.RTCSignalingStateStable) {
      this._isNegotiating = false;

      // HACK: Firefox doesn't yet support removing tracks when signalingState != 'stable'
      this._debug("flushing sender queue ${this._sendersAwaitingStable}");
      this._sendersAwaitingStable.forEach((sender) {
        this._pc.removeTrack(sender.sender);
        this._queuedNegotiation = true;
      });
      this._sendersAwaitingStable.clear();

      if (this._queuedNegotiation) {
        this._debug("flushing negotiation queue");
        this._queuedNegotiation = false;
        this._needsNegotiation(); // negotiate again
      } else {
        this._debug("negotiated");
        this.emit(const SimplePeerEvent.negotiated());
      }
    }

    this._debug("signalingStateChange ${this._pc.signalingState}");
    this.emit(SimplePeerEvent.signalingStateChange(this._pc.signalingState!));
  }

  void _onIceCandidate(RTCIceCandidate? candidate) {
    if (this.destroyed) return;
    if (candidate != null && this.opts.trickle) {
      this.emit(SimplePeerEvent.signal({
        "type": "candidate",
        "candidate": candidate.toMap(),
      }));
    } else if (candidate == null && !this._iceComplete) {
      this._iceComplete = true;
      this.emit(const SimplePeerEvent.iceComplete());
    }
    // as soon as we've received one valid candidate start timeout
    if (candidate != null) {
      this._startIceCompleteTimeout();
    }
  }

  void _onChannelMessage(RTCDataChannelMessage event) {
    if (this.destroyed) return;
    // TODO:
    // var data = event.data;
    // if (data is ByteBuffer) {
    //   data = Uint8List.view(data);
    // }
    // this.push(data);
  }

  void _onChannelBufferedAmountLow() {
    if (this.destroyed || this._cb == null) return;
    // this._debug(
    //   "ending backpressure: bufferedAmount ${this._channel!.bufferedAmount}",
    // );
    final cb = this._cb!;
    this._cb = null;
    cb(null);
  }

  void _onChannelOpen() {
    if (this._connected || this.destroyed) return;
    this._debug("on channel open");
    this._channelReady = true;
    this._maybeReady();
  }

  void _onChannelClose() {
    if (this.destroyed) return;
    this._debug("on channel close");
    this.destroy();
  }

  void _onTrack(RTCTrackEvent event) {
    if (this.destroyed) return;

    event.streams.forEach((eventStream) {
      this._debug("on track");
      this.emit(SimplePeerEvent.track(track: event.track, stream: eventStream));
      // TODO:
      // this._remoteTracks.add({
      //   "track": event.track,
      //   "stream": eventStream,
      // });
      this._remoteTracks.add(event.track);

      if (this._remoteStreams.any((remoteStream) {
        return remoteStream.id == eventStream.id;
      })) {
        return; // Only fire one 'stream' event, even though there may be multiple tracks per stream
      }

      this._remoteStreams.add(eventStream);
      Future.delayed(Duration.zero, () {
        this._debug("on stream");
        this.emit(SimplePeerEvent.stream(
            eventStream)); // ensure all tracks have been added
      });
    });
  }

  void _debug(String message) {
    print("[" + this._id + "] " + message);
  }

  /**
 * Expose peer and data channel config for overriding all Peer
 * instances. Otherwise, just set opts.config or opts.channelConfig
 * when constructing a Peer.
 */
  static var defaultConfig = {
    "iceServers": [
      {
        "urls": [
          "stun:stun.l.google.com:19302",
          "stun:global.stun.twilio.com:3478",
        ],
      },
    ],
    "sdpSemantics": "unified-plan",
  };

  static var defaultChannelConfig = RTCDataChannelInit();
}

// Peer.WEBRTC_SUPPORT = !!getBrowserRTC();

// HACK: Filter trickle lines when trickle is disabled #354
String filterTrickle(String sdp) {
  return sdp.replaceAll(RegExp(r"a=ice-options:trickle\s\n"), "");
}

void warn(message) {
  _log.w(message);
}

SimplePeerError errCode(Object? err, String code, [StackTrace? stackTrace]) {
  return SimplePeerError(
    code,
    err ?? Exception(code),
    stackTrace ?? StackTrace.current,
  );
}

class SimplePeerError {
  final Object error;
  final StackTrace stackTrace;
  final String code;

  const SimplePeerError(
    this.code,
    this.error,
    this.stackTrace,
  );

  @override
  String toString() {
    return 'SimplePeerError(code: $code, error: $error, stackTrace: $stackTrace)';
  }
}

class SignalData {
  final bool? renegotiate;
  final TransceiverRequest? transceiverRequest;
  final RTCIceCandidate? candidate;
  final String? sdp;
  final String? type;

  SignalData({
    this.renegotiate,
    this.transceiverRequest,
    this.candidate,
    this.sdp,
    this.type,
  });

  factory SignalData.fromJson(Map<String, Object?> json) {
    final transceiverRequest =
        json["transceiverRequest"] as Map<String, Object?>?;
    TransceiverRequest? _value;
    if (transceiverRequest != null) {
      _value = TransceiverRequest(
        kind:
            typeStringToRTCRtpMediaType[transceiverRequest["kind"] as String]!,
        init: RTCRtpTransceiverInit(
          direction: typeStringToRtpTransceiverDirection[
              transceiverRequest["init"] as String]!,
        ),
      );
    }
    final candidate = json["candidate"] as Map<String, Object?>?;
    RTCIceCandidate? _candidate;
    if (candidate != null) {
      _candidate = RTCIceCandidate(
        candidate["candidate"] as String?,
        candidate["sdpMin"] as String?,
        candidate["sdpMLineIndex"] as int?,
      );
    }
    return SignalData(
      renegotiate: json["renegotiate"] as bool?,
      transceiverRequest: _value,
      candidate: _candidate,
      sdp: json["sdp"] as String?,
      type: json["type"] as String?,
    );
  }
}

class TransceiverRequest {
  final RTCRtpMediaType kind;
  final RTCRtpTransceiverInit init;

  TransceiverRequest({required this.kind, required this.init});
}

class RTCRtpSenderWithDelete {
  final RTCRtpSender sender;
  bool removed;

  RTCRtpSenderWithDelete(this.sender, {this.removed = false});
}
