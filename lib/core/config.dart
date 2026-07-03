class AppConfig {
  static const String appName = 'TG CHAT';
  static const String defaultSystemPrompt = '';
  static const String defaultUserPrefix = '用户：';
  static const String defaultAssistantPrefix = 'TGAI：';
  static const String defaultPromptTemplate = '{history}{userPrefix}{input}\n{assistantPrefix}';
  static const double defaultTemperature = 0.8;
  static const int defaultMaxTokens = 256;
  static const int defaultContextLength = 512;
  static const int defaultTopK = 40;
  static const double defaultTopP = 0.95;
  static const double defaultRepeatPenalty = 1.1;
  static const int defaultRepeatLastN = 64;
  static const int defaultPrefillWindow = 64;
  static const int defaultDecodeWindow = 16;
  static const int defaultNThreads = 4;
  static const bool defaultUseACL = true;
}
