import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:rhasspy_mobile_app/utilits/JsonHelperClass.dart';

class RhasspyMqttApi {
  int port;
  String host;
  bool ssl;
  String username;
  String password;
  String siteId;
  MqttServerClient client;
  bool isConnected = false;
  String _currentSessionId;
  void Function(HermesNluIntentParsed) onReceivedIntent;
  void Function(HermesTextCaptured) onReceivedText;
  void Function(List<int>) onReceivedAudio;
  void Function(HermesEndSession) onReceivedEndSession;
  void Function(HermesContinueSession) onReceivedContinueSession;
  List<int> Function() captureAudio;
  RhasspyMqttApi(
      this.host, this.port, this.ssl, this.username, this.password, this.siteId,
      {this.onReceivedIntent,
      this.onReceivedText,
      this.onReceivedAudio,
      this.onReceivedEndSession,
      this.onReceivedContinueSession}) {
    client = MqttServerClient.withPort(host, siteId, port);
    client.keepAlivePeriod = 20;
    client.onConnected = onConnected;
    client.onSubscribed = onSubscribed;
    client.onDisconnected = onDisconnected;
    client.pongCallback = pong;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(siteId)
        .keepAliveFor(20)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;
  }

  /// Before doing any operation, you must call the service.
  /// Its return codes are 0 connection successfully made
  /// 1 connection failed and 2 incorrect credentials.
  Future<int> connect() async {
    try {
      await client.connect(username, password);
    } on Exception {
      isConnected = false;
      client.disconnect();
      return 1;
    }
    if (client.connectionStatus.state == MqttConnectionState.connected) {
      print('Mosquitto client connected');
      isConnected = true;
      client.updates.listen((value) => onReciviedMessages(value));
      client.subscribe("hermes/audioServer/${siteId.trim()}/playBytes/#",
          MqttQos.atLeastOnce);
      client.subscribe("hermes/asr/textCaptured", MqttQos.atLeastOnce);
      client.subscribe(
          "hermes/dialogueManager/endSession", MqttQos.atLeastOnce);
      client.subscribe("hermes/nlu/intentParsed", MqttQos.atLeastOnce);
      client.subscribe(
          "hermes/dialogueManager/continueSession", MqttQos.atLeastOnce);

      return 0;
    } else {
      /// Use status here rather than state if you also want the broker return code.
      client.disconnect();
      isConnected = false;
      return 1;
    }
  }

  void _publishString(String topic, [String data]) {
    final builder = MqttClientPayloadBuilder();
    if (data != null) builder.addUTF8String(data);
    client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload);
  }

  void _publishBytes(String topic, Uint8List data) {
    var buffer = MqttByteBuffer.fromList(data);
    final builder = MqttClientPayloadBuilder();
    if (data != null) builder.addBuffer(buffer.buffer);
    client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload);
  }

  void hermesAsrStartListening(
      {String sessionId,
      String wakewordId,
      bool stopInSilence = true,
      bool sendAudioCaptured = false}) {
    _publishString(
        "hermes/asr/startListening",
        json.encode({
          "siteId": "$siteId",
          "sessionId": "$sessionId",
          "lang": null,
          "stopOnSilence": stopInSilence,
          "sendAudioCaptured": sendAudioCaptured,
          "wakewordId": "$wakewordId",
          "intentFilter": null
        }));
  }

  void publishAudioFrame(Uint8List dataAudio) {
    _publishBytes("hermes/audioServer/$siteId/audioFrame", dataAudio);
  }

  void hermesAsrToggleOn({String reason = "playAudio"}) {
    _publishString("hermes/asr/toggleOn",
        json.encode({"siteId": "$siteId", "reason": "$reason"}));
  }

  void hermesAsrStopListening({String sessionId}) {
    _publishString("hermes/asr/stopListening",
        json.encode({"siteId": "$siteId", "sessionId": "$sessionId"}));
  }

  void hermesSessionStart() {
    // _publishString("hermes/dialogueManager/startSession", json.encode())
  }
  /// the function prepare rhasspy to listen at voice command and 
  /// then send [dataAudio] to hermes/audioServer/$siteId/audioFrame.
  /// if [cleanSession] is true after the command stopListening 
  /// delete the sessionId.
  void speechTotext(Uint8List dataAudio, {bool cleanSession = true}) {
    if (_currentSessionId == null) _currentSessionId = generateId();
    hermesAsrToggleOn();
    hermesAsrStartListening(sessionId: _currentSessionId);
    publishAudioFrame(dataAudio);
    hermesAsrStopListening(sessionId: _currentSessionId);
    if (cleanSession) {
      _currentSessionId = null;
    }
  }

  String getRandomString(int length) {
    Random rnd = Random();
    const chars = 'abcdef1234567890';
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  String generateId() {
    String randomString = getRandomString(36);
    randomString = randomString.replaceRange(8, 9, "-");
    randomString = randomString.replaceRange(13, 14, "-");
    randomString = randomString.replaceRange(18, 19, "-");
    randomString = randomString.replaceRange(23, 24, "-");
    return randomString;
  }

  void hermesTtsSay(String text, {String id, String sessionId = ""}) {
    if (id == null) id = generateId();
    _publishString(
        "hermes/tts/say",
        json.encode({
          "text": "$text",
          "siteId": "$siteId",
          "lang": null, // override language for TTS system
          "id": "$id",
          "sessionId": "$sessionId"
        }));
  }

  void hermesNluQuery(String input,
      {String id,
      List<String> intentFilter,
      String sessionId,
      String wakeWordId,
      String lang}) {
    _publishString(
        "hermes/nlu/query",
        json.encode({
          "input": "$input",
          "siteId": siteId,
          "id": id,
          "intentFilter": intentFilter,
          "sessionId": sessionId,
          "wakewordId": wakeWordId,
          "lang": lang
        }));
  }

  void textToIntent(String text, {bool handle = true}) {
    if (handle) {
      if (_currentSessionId == null) _currentSessionId = generateId();
    } else {
      _currentSessionId = null;
    }
    hermesNluQuery(text, sessionId: _currentSessionId);
  }

  void textToSpeech(String text, {bool generateSessionId = false}) {
    if (generateSessionId) {
      if (_currentSessionId == null) _currentSessionId = generateId();
    }
    hermesTtsSay(text, sessionId: _currentSessionId);
  }

  onReciviedMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    var lastMessage = messages[0];
    print("topic: ${lastMessage.topic}");
    if (lastMessage.topic.contains("hermes/audioServer/$siteId/playBytes/")) {
      print("recivied audio");
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      var buffer = recMessPayload.payload.message;
      onReceivedAudio(buffer.toList());
    }
    if (lastMessage.topic == "hermes/asr/textCaptured") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      HermesTextCaptured textCaptured = HermesTextCaptured.fromJson(json.decode(
          MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));
      if (textCaptured.siteId == siteId) onReceivedText(textCaptured);
    }
    if (lastMessage.topic == "hermes/dialogueManager/endSession") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      HermesEndSession endSession = HermesEndSession.fromJson(json.decode(
          MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));

      if (endSession.siteId == siteId) {
        hermesTtsSay(endSession.text, sessionId: _currentSessionId);
        onReceivedEndSession(endSession);
        _currentSessionId = null;
      }
    }
    if (lastMessage.topic == "hermes/dialogueManager/continueSession") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      HermesContinueSession continueSession = HermesContinueSession.fromJson(
          json.decode(MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));

      if (continueSession.siteId == siteId) {
        hermesTtsSay(continueSession.text, sessionId: _currentSessionId);
        onReceivedContinueSession(continueSession);
      }
    }
    if (lastMessage.topic == "hermes/nlu/intentParsed") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      HermesNluIntentParsed intentParsed = HermesNluIntentParsed.fromJson(
          json.decode(MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));
      if (intentParsed.siteId == siteId) onReceivedIntent(intentParsed);
    }
  }

  void onDisconnected() {
    print("Disconetted");
    isConnected = false;
  }

  void onConnected() {
    print("Conneted");
    isConnected = true;
  }

  void disconnect() {
    client.disconnect();
  }

  void onSubscribed(String topic) {}

  void pong() {
    print("pong");
  }
}
