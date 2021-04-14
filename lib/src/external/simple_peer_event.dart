import 'package:flutter_webrtc/flutter_webrtc.dart';

abstract class SimplePeerEvent {
  const SimplePeerEvent._();

  const factory SimplePeerEvent.error(
    Object error,
  ) = _Error;
  const factory SimplePeerEvent.close() = _Close;
  const factory SimplePeerEvent.iceTimeout() = _IceTimeout;
  const factory SimplePeerEvent.iceComplete() = _IceComplete;
  const factory SimplePeerEvent.signal(
    Map<String, Object?> /*SimplePeerSignal*/ signal,
  ) = _Signal;
  const factory SimplePeerEvent.iceStateChange({
    required RTCIceConnectionState? iceConnectionState,
    required RTCIceGatheringState? iceGatheringState,
  }) = _IceStateChange;
  const factory SimplePeerEvent.connect() = _Connect;
  const factory SimplePeerEvent.negotiated() = _Negotiated;
  const factory SimplePeerEvent.signalingStateChange(
    RTCSignalingState signalingState,
  ) = _SignalingStateChange;
  const factory SimplePeerEvent.track({
    required MediaStreamTrack track,
    required MediaStream stream,
  }) = _Track;
  const factory SimplePeerEvent.stream(
    MediaStream stream,
  ) = _Stream;

  T when<T>({
    required T Function(Object error) error,
    required T Function() close,
    required T Function() iceTimeout,
    required T Function() iceComplete,
    required T Function(Map<String, Object?> /*SimplePeerSignal*/ signal)
        signal,
    required T Function(RTCIceConnectionState? iceConnectionState,
            RTCIceGatheringState? iceGatheringState)
        iceStateChange,
    required T Function() connect,
    required T Function() negotiated,
    required T Function(RTCSignalingState signalingState) signalingStateChange,
    required T Function(MediaStreamTrack track, MediaStream stream) track,
    required T Function(MediaStream stream) stream,
  }) {
    final v = this;
    if (v is _Error) return error(v.error);
    if (v is _Close) return close();
    if (v is _IceTimeout) return iceTimeout();
    if (v is _IceComplete) return iceComplete();
    if (v is _Signal) return signal(v.signal);
    if (v is _IceStateChange)
      return iceStateChange(v.iceConnectionState, v.iceGatheringState);
    if (v is _Connect) return connect();
    if (v is _Negotiated) return negotiated();
    if (v is _SignalingStateChange)
      return signalingStateChange(v.signalingState);
    if (v is _Track) return track(v.track, v.stream);
    if (v is _Stream) return stream(v.stream);
    throw "";
  }

  T maybeWhen<T>({
    required T Function() orElse,
    T Function(Object error)? error,
    T Function()? close,
    T Function()? iceTimeout,
    T Function()? iceComplete,
    T Function(Map<String, Object?> /*SimplePeerSignal*/ signal)? signal,
    T Function(RTCIceConnectionState? iceConnectionState,
            RTCIceGatheringState? iceGatheringState)?
        iceStateChange,
    T Function()? connect,
    T Function()? negotiated,
    T Function(RTCSignalingState signalingState)? signalingStateChange,
    T Function(MediaStreamTrack track, MediaStream stream)? track,
    T Function(MediaStream stream)? stream,
  }) {
    final v = this;
    if (v is _Error) return error != null ? error(v.error) : orElse.call();
    if (v is _Close) return close != null ? close() : orElse.call();
    if (v is _IceTimeout)
      return iceTimeout != null ? iceTimeout() : orElse.call();
    if (v is _IceComplete)
      return iceComplete != null ? iceComplete() : orElse.call();
    if (v is _Signal) return signal != null ? signal(v.signal) : orElse.call();
    if (v is _IceStateChange)
      return iceStateChange != null
          ? iceStateChange(v.iceConnectionState, v.iceGatheringState)
          : orElse.call();
    if (v is _Connect) return connect != null ? connect() : orElse.call();
    if (v is _Negotiated)
      return negotiated != null ? negotiated() : orElse.call();
    if (v is _SignalingStateChange)
      return signalingStateChange != null
          ? signalingStateChange(v.signalingState)
          : orElse.call();
    if (v is _Track)
      return track != null ? track(v.track, v.stream) : orElse.call();
    if (v is _Stream) return stream != null ? stream(v.stream) : orElse.call();
    throw "";
  }

  T map<T>({
    required T Function(_Error value) error,
    required T Function(_Close value) close,
    required T Function(_IceTimeout value) iceTimeout,
    required T Function(_IceComplete value) iceComplete,
    required T Function(_Signal value) signal,
    required T Function(_IceStateChange value) iceStateChange,
    required T Function(_Connect value) connect,
    required T Function(_Negotiated value) negotiated,
    required T Function(_SignalingStateChange value) signalingStateChange,
    required T Function(_Track value) track,
    required T Function(_Stream value) stream,
  }) {
    final v = this;
    if (v is _Error) return error(v);
    if (v is _Close) return close(v);
    if (v is _IceTimeout) return iceTimeout(v);
    if (v is _IceComplete) return iceComplete(v);
    if (v is _Signal) return signal(v);
    if (v is _IceStateChange) return iceStateChange(v);
    if (v is _Connect) return connect(v);
    if (v is _Negotiated) return negotiated(v);
    if (v is _SignalingStateChange) return signalingStateChange(v);
    if (v is _Track) return track(v);
    if (v is _Stream) return stream(v);
    throw "";
  }

  T maybeMap<T>({
    required T Function() orElse,
    T Function(_Error value)? error,
    T Function(_Close value)? close,
    T Function(_IceTimeout value)? iceTimeout,
    T Function(_IceComplete value)? iceComplete,
    T Function(_Signal value)? signal,
    T Function(_IceStateChange value)? iceStateChange,
    T Function(_Connect value)? connect,
    T Function(_Negotiated value)? negotiated,
    T Function(_SignalingStateChange value)? signalingStateChange,
    T Function(_Track value)? track,
    T Function(_Stream value)? stream,
  }) {
    final v = this;
    if (v is _Error) return error != null ? error(v) : orElse.call();
    if (v is _Close) return close != null ? close(v) : orElse.call();
    if (v is _IceTimeout)
      return iceTimeout != null ? iceTimeout(v) : orElse.call();
    if (v is _IceComplete)
      return iceComplete != null ? iceComplete(v) : orElse.call();
    if (v is _Signal) return signal != null ? signal(v) : orElse.call();
    if (v is _IceStateChange)
      return iceStateChange != null ? iceStateChange(v) : orElse.call();
    if (v is _Connect) return connect != null ? connect(v) : orElse.call();
    if (v is _Negotiated)
      return negotiated != null ? negotiated(v) : orElse.call();
    if (v is _SignalingStateChange)
      return signalingStateChange != null
          ? signalingStateChange(v)
          : orElse.call();
    if (v is _Track) return track != null ? track(v) : orElse.call();
    if (v is _Stream) return stream != null ? stream(v) : orElse.call();
    throw "";
  }
}

class _Error extends SimplePeerEvent {
  final Object error;

  const _Error(
    this.error,
  ) : super._();
}

class _Close extends SimplePeerEvent {
  const _Close() : super._();
}

class _IceTimeout extends SimplePeerEvent {
  const _IceTimeout() : super._();
}

class _IceComplete extends SimplePeerEvent {
  const _IceComplete() : super._();
}

class _Signal extends SimplePeerEvent {
  final Map<String, Object?> /*SimplePeerSignal*/ signal;

  const _Signal(
    this.signal,
  ) : super._();
}

class _IceStateChange extends SimplePeerEvent {
  final RTCIceConnectionState? iceConnectionState;
  final RTCIceGatheringState? iceGatheringState;

  const _IceStateChange({
    required this.iceConnectionState,
    required this.iceGatheringState,
  }) : super._();
}

class _Connect extends SimplePeerEvent {
  const _Connect() : super._();
}

class _Negotiated extends SimplePeerEvent {
  const _Negotiated() : super._();
}

class _SignalingStateChange extends SimplePeerEvent {
  final RTCSignalingState signalingState;

  const _SignalingStateChange(
    this.signalingState,
  ) : super._();
}

class _Track extends SimplePeerEvent {
  final MediaStreamTrack track;
  final MediaStream stream;

  const _Track({
    required this.track,
    required this.stream,
  }) : super._();
}

class _Stream extends SimplePeerEvent {
  final MediaStream stream;

  const _Stream(
    this.stream,
  ) : super._();
}
