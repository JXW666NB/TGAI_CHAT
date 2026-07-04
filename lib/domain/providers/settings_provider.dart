import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config.dart';
import '../../services/pytorch_service.dart';

class SettingsProvider extends ChangeNotifier {
  late SharedPreferences _prefs;
  bool _initialized = false;

  bool get initialized => _initialized;

  // 设备信息（从原生获取）
  Map<String, dynamic> _deviceInfo = {};
  Map<String, dynamic> get deviceInfo => _deviceInfo;
  bool _deviceInfoLoaded = false;
  bool get deviceInfoLoaded => _deviceInfoLoaded;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
    notifyListeners();
    // 后台获取设备信息，不阻塞启动
    fetchDeviceInfo();
  }

  Future<void> fetchDeviceInfo() async {
    try {
      final info = await PytorchService().getDeviceInfo();
      if (info != null) {
        _deviceInfo = info;
        _deviceInfoLoaded = true;
        notifyListeners();
      }
    } catch (_) {
      // 设备信息获取失败不影响使用
    }
  }

  double get temperature => _prefs.getDouble('temperature') ?? AppConfig.defaultTemperature;
  set temperature(double v) {
    _prefs.setDouble('temperature', v);
    notifyListeners();
  }

  int get maxTokens => _prefs.getInt('maxTokens') ?? AppConfig.defaultMaxTokens;
  set maxTokens(int v) {
    _prefs.setInt('maxTokens', v);
    notifyListeners();
  }

  int get contextLength => _prefs.getInt('contextLength') ?? AppConfig.defaultContextLength;
  set contextLength(int v) {
    _prefs.setInt('contextLength', v);
    notifyListeners();
  }

  int get topK => _prefs.getInt('topK') ?? AppConfig.defaultTopK;
  set topK(int v) {
    _prefs.setInt('topK', v);
    notifyListeners();
  }

  double get topP => _prefs.getDouble('topP') ?? AppConfig.defaultTopP;
  set topP(double v) {
    _prefs.setDouble('topP', v);
    notifyListeners();
  }

  double get repeatPenalty => _prefs.getDouble('repeatPenalty') ?? AppConfig.defaultRepeatPenalty;
  set repeatPenalty(double v) {
    _prefs.setDouble('repeatPenalty', v);
    notifyListeners();
  }

  int get repeatLastN => _prefs.getInt('repeatLastN') ?? AppConfig.defaultRepeatLastN;
  set repeatLastN(int v) {
    _prefs.setInt('repeatLastN', v);
    notifyListeners();
  }

  String get systemPrompt => _prefs.getString('systemPrompt') ?? AppConfig.defaultSystemPrompt;
  set systemPrompt(String v) {
    _prefs.setString('systemPrompt', v);
    notifyListeners();
  }

  String get promptTemplate => _prefs.getString('promptTemplate') ?? AppConfig.defaultPromptTemplate;
  set promptTemplate(String v) {
    _prefs.setString('promptTemplate', v);
    notifyListeners();
  }

  String get userPrefix => _prefs.getString('userPrefix') ?? AppConfig.defaultUserPrefix;
  set userPrefix(String v) {
    _prefs.setString('userPrefix', v);
    notifyListeners();
  }

  String get assistantPrefix => _prefs.getString('assistantPrefix') ?? AppConfig.defaultAssistantPrefix;
  set assistantPrefix(String v) {
    _prefs.setString('assistantPrefix', v);
    notifyListeners();
  }

  int get nThreads => _prefs.getInt('nThreads') ?? AppConfig.defaultNThreads;
  set nThreads(int v) {
    _prefs.setInt('nThreads', v);
    notifyListeners();
  }

  int get prefillWindow => _prefs.getInt('prefillWindow') ?? AppConfig.defaultPrefillWindow;
  set prefillWindow(int v) {
    _prefs.setInt('prefillWindow', v);
    notifyListeners();
  }

  int get decodeWindow => _prefs.getInt('decodeWindow') ?? AppConfig.defaultDecodeWindow;
  set decodeWindow(int v) {
    _prefs.setInt('decodeWindow', v);
    notifyListeners();
  }

  bool get useACL => _prefs.getBool('useACL') ?? AppConfig.defaultUseACL;
  set useACL(bool v) {
    _prefs.setBool('useACL', v);
    notifyListeners();
  }

  String get providerMode => _prefs.getString('providerMode') ?? AppConfig.defaultProviderMode;
  set providerMode(String v) {
    _prefs.setString('providerMode', v);
    notifyListeners();
  }

  bool get debugMode => _prefs.getBool('debugMode') ?? false;
  set debugMode(bool v) {
    _prefs.setBool('debugMode', v);
    notifyListeners();
  }

  Map<String, dynamic> toDebugMap() => {
        'temperature': temperature,
        'maxTokens': maxTokens,
        'contextLength': contextLength,
        'topK': topK,
        'topP': topP,
        'repeatPenalty': repeatPenalty,
        'repeatLastN': repeatLastN,
        'nThreads': nThreads,
        'systemPrompt': systemPrompt,
        'promptTemplate': promptTemplate,
        'userPrefix': userPrefix,
        'assistantPrefix': assistantPrefix,
      };

  String toDebugJson() => const JsonEncoder.withIndent('  ').convert(toDebugMap());

  Future<void> resetToDefaults() async {
    await _prefs.remove('temperature');
    await _prefs.remove('maxTokens');
    await _prefs.remove('contextLength');
    await _prefs.remove('topK');
    await _prefs.remove('topP');
    await _prefs.remove('repeatPenalty');
    await _prefs.remove('repeatLastN');
    await _prefs.remove('systemPrompt');
    await _prefs.remove('promptTemplate');
    await _prefs.remove('userPrefix');
    await _prefs.remove('assistantPrefix');
    await _prefs.remove('nThreads');
    await _prefs.remove('prefillWindow');
    await _prefs.remove('decodeWindow');
    await _prefs.remove('useACL');
    await _prefs.remove('providerMode');
    notifyListeners();
  }
}
