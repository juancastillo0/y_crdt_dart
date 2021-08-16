/**
 * Testing if encoding/decoding compatibility and integration compatiblity is given.
 * We expect that the document always looks the same, even if we upgrade the integration algorithm, or add additional encoding approaches.
 *
 * The v1 documents were generated with Yjs v13.2.0 based on the randomisized tests.
 */
import 'dart:convert';

import 'package:y_crdt/src/lib0/testing.dart' as t;
import 'package:y_crdt/y_crdt.dart' as Y;

Future<void> main() async {
  await t.runTests(
    {
      "compatibility": {
        "testArrayCompatibilityV1": testArrayCompatibilityV1,
        "testMapDecodingCompatibilityV1": testMapDecodingCompatibilityV1,
        "testTextDecodingCompatibilityV1": testTextDecodingCompatibilityV1,
      }
    },
  );
}

/**
 * @param {t.TestCase} tc
 */
void testArrayCompatibilityV1(t.TestCase tc) {
  const oldDoc =
      "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";
  final oldVal = jsonDecode(
      '[[1,2,3,4],472,472,{"someprop":44},472,[1,2,3,4],{"someprop":44},[1,2,3,4],[1,2,3,4],[1,2,3,4],{"someprop":44},449,448,[1,2,3,4],[1,2,3,4],{"someprop":44},452,{"someprop":44},[1,2,3,4],[1,2,3,4],[1,2,3,4],[1,2,3,4],452,[1,2,3,4],497,{"someprop":44},497,497,497,{"someprop":44},[1,2,3,4],522,522,452,470,{"someprop":44},[1,2,3,4],453,{"someprop":44},480,480,480,508,508,508,[1,2,3,4],[1,2,3,4],502,492,492,453,{"someprop":44},496,496,496,[1,2,3,4],496,493,495,495,495,495,493,[1,2,3,4],493,493,453,{"someprop":44},{"someprop":44},505,505,517,517,505,[1,2,3,4],{"someprop":44},509,{"someprop":44},521,521,521,509,477,{"someprop":44},{"someprop":44},485,485,{"someprop":44},515,{"someprop":44},451,{"someprop":44},[1,2,3,4],516,516,516,516,{"someprop":44},499,499,469,469,[1,2,3,4],[1,2,3,4],512,512,512,{"someprop":44},454,487,487,487,[1,2,3,4],[1,2,3,4],454,[1,2,3,4],[1,2,3,4],{"someprop":44},[1,2,3,4],459,[1,2,3,4],513,459,{"someprop":44},[1,2,3,4],482,{"someprop":44},[1,2,3,4],[1,2,3,4],459,[1,2,3,4],{"someprop":44},[1,2,3,4],484,454,510,510,510,510,468,{"someprop":44},468,[1,2,3,4],[1,2,3,4],[1,2,3,4],[1,2,3,4],467,[1,2,3,4],467,486,486,486,[1,2,3,4],489,451,[1,2,3,4],{"someprop":44},[1,2,3,4],[1,2,3,4],{"someprop":44},{"someprop":44},483,[1,2,3,4],{"someprop":44},{"someprop":44},{"someprop":44},{"someprop":44},519,519,519,519,506,506,[1,2,3,4],{"someprop":44},464,{"someprop":44},481,481,[1,2,3,4],{"someprop":44},[1,2,3,4],464,475,475,475,463,{"someprop":44},[1,2,3,4],518,[1,2,3,4],[1,2,3,4],463,455,498,498,498,466,471,471,471,501,[1,2,3,4],501,501,476,{"someprop":44},466,[1,2,3,4],{"someprop":44},503,503,503,466,455,490,474,{"someprop":44},457,494,494,{"someprop":44},457,479,{"someprop":44},[1,2,3,4],500,500,500,{"someprop":44},[1,2,3,4],[1,2,3,4],{"someprop":44},{"someprop":44},{"someprop":44},[1,2,3,4],[1,2,3,4],{"someprop":44},[1,2,3,4],[1,2,3,4],[1,2,3,4],[1,2,3],491,491,[1,2,3,4],504,504,504,504,465,[1,2,3,4],{"someprop":44},460,{"someprop":44},488,488,488,[1,2,3,4],[1,2,3,4],{"someprop":44},{"someprop":44},514,514,514,514,{"someprop":44},{"someprop":44},{"someprop":44},458,[1,2,3,4],[1,2,3,4],462,[1,2,3,4],[1,2,3,4],{"someprop":44},462,{"someprop":44},[1,2,3,4],{"someprop":44},[1,2,3,4],507,{"someprop":44},{"someprop":44},507,507,{"someprop":44},{"someprop":44},[1,2,3,4],{"someprop":44},461,{"someprop":44},473,461,[1,2,3,4],461,511,511,461,{"someprop":44},{"someprop":44},520,520,520,[1,2,3,4],458]');
  final doc = Y.Doc();
  Y.applyUpdate(doc, base64.decode(oldDoc), null);
  t.compare(doc.getArray("array").toJSON(), oldVal);
}

/**
 * @param {t.TestCase} tc
 */
void testMapDecodingCompatibilityV1(t.TestCase tc) {
  const oldDoc =
      "BVcEAKEBAAGhAwEBAAShBAABAAGhBAECoQEKAgAEoQQLAQAEoQMcAaEEFQGhAiECAAShAS4BoQQYAaEEHgGhBB8BoQQdAQABoQQhAaEEIAGhBCMBAAGhBCUCoQQkAqEEKAEABKEEKgGhBCsBoQQwAQABoQQxAaEEMgGhBDQBAAGhBDYBoQQ1AQAEoQQ5AQABoQQ4AQAEoQM6AQAEoQRFAaEESgEAAaEESwEABKEETQGhBEABoQRSAgABoQRTAgAEoQRVAgABoQReAaEEWAEABKEEYAEAAaEEZgKhBGECAAShBGsBAAGhAaUBAgAEoQRwAgABoQRzAQAEoQR5AQABoQSAAQEABKEEggEBAAGhBIcBAwABoQGzAQEAAaEEjQECpwHMAQAIAASRAQR9AX0CfQN9BGcDACEBA21hcAN0d28BoQMAAQAEoQMBAQABoQMGAQAEIQEDbWFwA29uZQOhBAEBAAShAw8CoQMQAaEDFgEAAaEDFwEAAaEDGAGhAxwBAAGhAx0BoQIaBAAEoQMjAgABoQMpAQABoQMfAQABoQMrAQABoQMvAaEDLQEAAaEDMQIABKEDNQGhAzIBoQM6AaEDPAGhBCMBAAGhAU8BAAGhA0ADoQJCAQABoQNEAgABoQNFAgAEoQJEAQABoQNLAaEEQAEABKEESgEAAaEDWAGhA1MBAAGhA1oBAAGhA10DoQNbAQABoQNhAwABoQNiAQAEoQNmAaEDaAWhA20BAAShA3IBAAGhA3MBAAShA3gBoQN6A6EDfwEAAaEDgwEBAAShA4UBAgABoQOLAQGhA4IBAaEDjQEBoQOOAQEAAaEDjwEBAAShA5ABAaEDkgEBoQOXAQEABKEDmQEBAAGhA5gBAQABoQOgAQEAAaEDngEBaQIAIQEDbWFwA3R3bwGhAwABoQEAAQABoQIBAQAEoQIEAaEDAQKhAQwDAAShAg4BAAShAhMBoQQJBAABoQQVAQABoQIeAaECHAGhBBgBAAShAiICAAShBB4BAAShBB8BAAGhAzwBAAGhBCMCoQM9AqEDPgEAAaECOQEABKECPAGhAkEBAAGhAjoBAAGhAkIBAAShAkQBAAShAksBAAGhA0UCAAShAlMCoQJQAQAEoQJZAaECWgEAAaECYAKhAl8BAAShAmMCAAGhAmoBoQJkAgAEoQRSAQABoQJzAQAEoQRTAQAEoQJ6AQAEoQJ1AQABoQKEAQEABKEChgEBoQJ/AgABoQKLAQEABKECjwECAAGhApUBAQABoQKXAQGhAo0BAQABoQKaAQGhApkBAQABoQKcAQEAAaECnwEBAAShAqEBAaECnQEBAAShAqYBAaECpwEBAAGhAqwBAQABoQKtAQEABKECrwECAAF5AQAhAQNtYXADb25lASEBA21hcAN0d28CAAGhAQABoQMAAaEBBAEAAaEBBQGhAQYBoQMPAaEEAQGhAQoBoQELAaEBDAEABKEBDgEAAaEBDQEABKEBFQEABKEDHAKhBBUBAAShASECAAShAScBoQQWAwAEoQIhAgABoQEvAaECIgEABKEBOAEAAaEBNwEAAaEBPwGhAzoBAAShAUIBoQQjAQABoQFIAQABoQFKAaEDPgEAAaECOgEAAaEBTwIAAaEBUgEAAaECQQGhAVQCoQFWAgABoQFYAQAEoQFcAqEBWgEAAaEBYgShAWMBAAGhAWgBAAGhAWkCAAGhAW4BAAGhAWsBAAShAXABAAShAXcCAAShAX0BAAShAYIBAaEBcgEAAaEBhwEBoQGIAQEABKEBigEBAAShAZABAQAEoQGLAQIABKEBlQEBAAShBGkEAAGhAagBAQAEoQRzAQABoQGvAQKhBHsBAAGhAbMBAgAEoQSAAQEAAaEBuwECAAGhAbYBAqEEiwEBAAShAcIBAQAEoQHHAQEABKEEkAEBpwHRAQEoAAHSAQdkZWVwa2V5AXcJZGVlcHZhbHVloQHMAQFiAAAhAQNtYXADb25lAwABoQACASEBA21hcAN0d28CAAShAAQBoQAGAaEACwEAAaEADQIABKEADAEABKEAEAEABKEAGgEABKEAHwEABKEAFQGhACQBAAGhACoBoQApAaEALAGhAC0BoQAuAaEALwEAAaEAMAIAAaEANAEABKEAMQEABKEANgEAAaEAQAIAAaEAOwGhAEMCAAShAEcBAAShAEwBoQBFAQAEoQBRAQAEoQBXAqEAUgEABKEAXgIAAaEAZAKhAF0BoQBnAqEAaAEABKEAawGhAGoCoQBwAQABoQBzAQAEoQB1AQABoQB6AaEAcgGhAHwBAAShAH4BoQB9AgABoQCFAQEABKEAhwEBAAShAIwBAaEAgwEBAAShAJIBAQAEoQCXAQIABKEAkQEBAAGhAJ0BAQAEoQCiAQEABKEApAECAAGhAK8BAqEAqQEBAAGhALMBAQABBQABALcBAQIA0gHUAQEEAQCRAQMBAKUBAgEAuQE=";
  // eslint-disable-next-line
  const oldVal = /** @type {any} */ {
    'one': [1, 2, 3, 4],
    'two': {'deepkey': "deepvalue"},
  };
  final doc = Y.Doc();
  Y.applyUpdate(doc, base64.decode(oldDoc), null);
  t.compare(doc.getMap("map").toJSON(), oldVal);
}

/**
 * @param {t.TestCase} tc
 */
void testTextDecodingCompatibilityV1(t.TestCase tc) {
  const oldDoc =
      "BS8EAAUBBHRleHRveyJpbWFnZSI6Imh0dHBzOi8vdXNlci1pbWFnZXMuZ2l0aHVidXNlcmNvbnRlbnQuY29tLzU1NTM3NTcvNDg5NzUzMDctNjFlZmIxMDAtZjA2ZC0xMWU4LTkxNzctZWU4OTVlNTkxNmU1LnBuZyJ9RAQAATHBBAEEAAHBBAIEAAHEBAMEAAQxdXUKxQQCBANveyJpbWFnZSI6Imh0dHBzOi8vdXNlci1pbWFnZXMuZ2l0aHVidXNlcmNvbnRlbnQuY29tLzU1NTM3NTcvNDg5NzUzMDctNjFlZmIxMDAtZjA2ZC0xMWU4LTkxNzctZWU4OTVlNTkxNmU1LnBuZyJ9xQMJBAFveyJpbWFnZSI6Imh0dHBzOi8vdXNlci1pbWFnZXMuZ2l0aHVidXNlcmNvbnRlbnQuY29tLzU1NTM3NTcvNDg5NzUzMDctNjFlZmIxMDAtZjA2ZC0xMWU4LTkxNzctZWU4OTVlNTkxNmU1LnBuZyJ9xQMJBAlveyJpbWFnZSI6Imh0dHBzOi8vdXNlci1pbWFnZXMuZ2l0aHVidXNlcmNvbnRlbnQuY29tLzU1NTM3NTcvNDg5NzUzMDctNjFlZmIxMDAtZjA2ZC0xMWU4LTkxNzctZWU4OTVlNTkxNmU1LnBuZyJ9xgMBAwIGaXRhbGljBHRydWXGBAsDAgVjb2xvcgYiIzg4OCLEBAwDAgExxAQNAwIBMsEEDgMCAsYEEAMCBml0YWxpYwRudWxsxgQRAwIFY29sb3IEbnVsbMQDAQQLATHEBBMECwIyOcQEFQQLCzl6anpueXdvaHB4xAQgBAsIY25icmNhcQrBAxADEQHGAR8BIARib2xkBHRydWXGAgACAQRib2xkBG51bGzFAwkECm97ImltYWdlIjoiaHR0cHM6Ly91c2VyLWltYWdlcy5naXRodWJ1c2VyY29udGVudC5jb20vNTU1Mzc1Ny80ODk3NTMwNy02MWVmYjEwMC1mMDZkLTExZTgtOTE3Ny1lZTg5NWU1OTE2ZTUucG5nIn3GARABEQZpdGFsaWMEdHJ1ZcYELQERBWNvbG9yBiIjODg4IsYBEgETBml0YWxpYwRudWxsxgQvARMFY29sb3IEbnVsbMYCKwIsBGJvbGQEdHJ1ZcYCLQIuBGJvbGQEbnVsbMYCjAECjQEGaXRhbGlj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xgKbAQQOBml0YWxpYwR0cnVlxgKcAQQOBWNvbG9yBiIjODg4IsECaAI7AcQCCgEBFjEzMThqd3NramFiZG5kcmRsbWphZQrGA1UDVgRib2xkBHRydWXGA1cDWARib2xkBG51bGzGAEAAQQZpdGFsaWMEdHJ1ZcYCtwEAQQRib2xkBG51bGzEArgBAEESMTMyNnJwY3pucWFob3BjcnRkxgLKAQBBBml0YWxpYwRudWxsxgLLAQBBBGJvbGQEdHJ1ZRkBAMUCAgIDb3siaW1hZ2UiOiJodHRwczovL3VzZXItaW1hZ2VzLmdpdGh1YnVzZXJjb250ZW50LmNvbS81NTUzNzU3LzQ4OTc1MzA3LTYxZWZiMTAwLWYwNmQtMTFlOC05MTc3LWVlODk1ZTU5MTZlNS5wbmcifcQCCgILBzEyOTN0agrGABgAGQRib2xkBHRydWXGAA0ADgRib2xkBG51bGxEAgAHMTMwNnJ1cMQBEAIAAnVqxAESAgANaWtrY2pucmNwc2Nrd8QBHwIAAQrFBBMEFG97ImltYWdlIjoiaHR0cHM6Ly91c2VyLWltYWdlcy5naXRodWJ1c2VyY29udGVudC5jb20vNTU1Mzc1Ny80ODk3NTMwNy02MWVmYjEwMC1mMDZkLTExZTgtOTE3Ny1lZTg5NWU1OTE2ZTUucG5nIn3FAx0DBW97ImltYWdlIjoiaHR0cHM6Ly91c2VyLWltYWdlcy5naXRodWJ1c2VyY29udGVudC5jb20vNTU1Mzc1Ny80ODk3NTMwNy02MWVmYjEwMC1mMDZkLTExZTgtOTE3Ny1lZTg5NWU1OTE2ZTUucG5nIn3GAlICUwRib2xkBHRydWXGAlQCVQRib2xkBG51bGzGAnsCfAZpdGFsaWMEdHJ1ZcYBJQJ8BWNvbG9yBiIjODg4IsYBJgJ8BGJvbGQEbnVsbMQBJwJ8CjEzMTRweWNhdnXGATECfAZpdGFsaWMEbnVsbMYBMgJ8BWNvbG9yBG51bGzBATMCfAHFADEAMm97ImltYWdlIjoiaHR0cHM6Ly91c2VyLWltYWdlcy5naXRodWJ1c2VyY29udGVudC5jb20vNTU1Mzc1Ny80ODk3NTMwNy02MWVmYjEwMC1mMDZkLTExZTgtOTE3Ny1lZTg5NWU1OTE2ZTUucG5nIn3GADUANgZpdGFsaWMEdHJ1ZcEANwA4AcQAMgAzEzEzMjJybmJhb2tvcml4ZW52cArEAgUCBhcxMzIzbnVjdnhzcWx6bndsZmF2bXBjCsYDDwMQBGJvbGQEdHJ1ZR0AAMQEAwQEDTEyOTVxZnJ2bHlmYXDEAAwEBAFjxAANBAQCanbBAAwADQHEABAADQEywQARAA0ExAAVAA0DZHZmxAAYAA0BYcYCAwIEBml0YWxpYwR0cnVlwQAaAgQCxAAcAgQEMDRrdcYAIAIEBml0YWxpYwRudWxsxQQgBCFveyJpbWFnZSI6Imh0dHBzOi8vdXNlci1pbWFnZXMuZ2l0aHVidXNlcmNvbnRlbnQuY29tLzU1NTM3NTcvNDg5NzUzMDctNjFlZmIxMDAtZjA2ZC0xMWU4LTkxNzctZWU4OTVlNTkxNmU1LnBuZyJ9xQJAABZveyJpbWFnZSI6Imh0dHBzOi8vdXNlci1pbWFnZXMuZ2l0aHVidXNlcmNvbnRlbnQuY29tLzU1NTM3NTcvNDg5NzUzMDctNjFlZmIxMDAtZjA2ZC0xMWU4LTkxNzctZWU4OTVlNTkxNmU1LnBuZyJ9xAQVBBYGMTMxMWtrxAIqAisIMTMxMnFyd3TEADECKwFixAAyAisDcnhxxAA1AisBasQANgIrAXjEADcCKwZkb3ZhbwrEAgAEKwMxMzHEAEAEKwkzYXhoa3RoaHXGAnoCewRib2xkBG51bGzFAEoCe297ImltYWdlIjoiaHR0cHM6Ly91c2VyLWltYWdlcy5naXRodWJ1c2VyY29udGVudC5jb20vNTU1Mzc1Ny80ODk3NTMwNy02MWVmYjEwMC1mMDZkLTExZTgtOTE3Ny1lZTg5NWU1OTE2ZTUucG5nIn3GAEsCewRib2xkBHRydWXEAl8CYBExMzE3cGZjeWhrc3JrcGt0CsQBHwQqCzEzMTliY2Nna3AKxAKSAQKTARUxMzIwY29oYnZjcmtycGpuZ2RvYwoFBAQCAg8CKQE1AQADEAESBBsCAwsGAhIBHgJAAk8CWwJfAmQDcQJ5AaABAQIOBAILAg4CIQIoAjcCPAJEAlgCagJwAXwClwEEngEBAQI0ATcB";
  // eslint-disable-next-line
  const oldVal = [
    {'insert': "1306rup"},
    {
      'insert': "uj",
      'attributes': {'italic': true, 'color': "#888"}
    },
    {'insert': "ikkcjnrcpsckw1319bccgkp\n"},
    {
      'insert': "\n1131",
      'attributes': {'bold': true}
    },
    {
      'insert': "1326rpcznqahopcrtd",
      'attributes': {'italic': true}
    },
    {
      'insert': "3axhkthhu",
      'attributes': {'bold': true}
    },
    {'insert': "28"},
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {'insert': "9"},
    {
      'insert': "04ku",
      'attributes': {'italic': true}
    },
    {'insert': "1323nucvxsqlznwlfavmpc\nu"},
    {
      'insert': "tc",
      'attributes': {'italic': true}
    },
    {'insert': "je1318jwskjabdndrdlmjae\n1293tj\nj1292qrmf"},
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {'insert': "k\nuf"},
    {
      'insert': "14hs",
      'attributes': {'italic': true}
    },
    {'insert': "13dccxdyxg"},
    {
      'insert': "zc",
      'attributes': {'italic': true, 'color': "#888"}
    },
    {'insert': "apo"},
    {
      'insert': "tn",
      'attributes': {'bold': true}
    },
    {'insert': "r"},
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {'insert': "gn\n"},
    {
      'insert': "z",
      'attributes': {'italic': true}
    },
    {'insert': "\n121"},
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {'insert': "291311kk9zjznywohpx"},
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {'insert': "cnbrcaq\n"},
    {
      'insert': "1",
      'attributes': {'italic': true, 'color': "#888"}
    },
    {'insert': "1310g"},
    {
      'insert': "ws",
      'attributes': {'italic': true, 'color': "#888"}
    },
    {'insert': "hxwych"},
    {
      'insert': "kq",
      'attributes': {'italic': true}
    },
    {'insert': "sdru1320cohbvcrkrpjngdoc\njqic\n"},
    {
      'insert': "2",
      'attributes': {'italic': true, 'color': "#888"}
    },
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {'insert': "90n1297zm"},
    {
      'insert': "v1309zlgvjx",
      'attributes': {'bold': true}
    },
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {
      'insert': "g",
      'attributes': {'bold': true}
    },
    {
      'insert': "1314pycavu",
      'attributes': {'italic': true, 'color': "#888"}
    },
    {'insert': "pkzqcj"},
    {
      'insert': "sa",
      'attributes': {'italic': true, 'color': "#888"}
    },
    {'insert': "sjy\n"},
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {'insert': "xr\n"},
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {'insert': "1"},
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {'insert': "1295qfrvlyfap201312qrwt"},
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {'insert': "b1322rnbaokorixenvp\nrxq"},
    {
      'insert': "j",
      'attributes': {'italic': true}
    },
    {
      'insert': "x",
      'attributes': {'italic': true, 'color': "#888"}
    },
    {
      'insert': "15mziwabzkrrmscvdovao\n0",
      'attributes': {'italic': true}
    },
    {
      'insert': "hx",
      'attributes': {'italic': true, 'bold': true}
    },
    {
      'insert': "ojeetrjhxkr13031317pfcyhksrkpkt\nuhv1",
      'attributes': {'italic': true},
    },
    {
      'insert': "32",
      'attributes': {'italic': true, 'color': "#888"}
    },
    {'insert': "4rorywthq1325iodbzizxhmlibvpyrxmq\n\nganln\nqne\n"},
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
    {'insert': "dvf"},
    {
      'insert': "ac",
      'attributes': {'bold': true}
    },
    {'insert': "1302xciwa"},
    {
      'insert': "1305rl",
      'attributes': {'bold': true}
    },
    {'insert': "08\n"},
    {
      'insert': "eyk",
      'attributes': {'bold': true}
    },
    {'insert': "y1321apgivydqsjfsehhezukiqtt1307tvjiejlh"},
    {
      'insert': "1316zlpkmctoqomgfthbpg",
      'attributes': {'bold': true}
    },
    {'insert': "gv"},
    {
      'insert': "lb",
      'attributes': {'bold': true}
    },
    {'insert': "f\nhntk\njv1uu\n"},
    {
      'insert': {
        'image':
            "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
      },
    },
  ];
  final doc = Y.Doc();
  Y.applyUpdate(doc, base64.decode(oldDoc), null);
  t.compare(doc.getText("text").toDelta(), oldVal);
}
