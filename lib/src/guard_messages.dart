import 'scanner.dart';

/// Localised user-facing messages per scanner/finding type.
///
/// Ships with 11 locales. Configurable via [customMessages] for overrides.
/// Tree-shakeable — import only if you need user-facing feedback.
///
/// ```dart
/// final msgs = GuardMessages();
/// print(msgs.message('pii', locale: 'es'));
/// // → Se detectó información personal y se gestionó.
/// ```
class GuardMessages {
  final Map<String, Map<String, String>> _custom;

  const GuardMessages(
      {Map<String, Map<String, String>> customMessages = const {}})
      : _custom = customMessages;

  /// Get a user-facing message for [scannerName] in [locale].
  ///
  /// Resolution order: custom override → built-in locale → English → generic.
  String message(String scannerName, {String locale = 'en'}) {
    final custom = _custom[locale]?[scannerName];
    if (custom != null) return custom;
    final builtIn = _builtIn[locale]?[scannerName];
    if (builtIn != null) return builtIn;
    final en = _builtIn['en']?[scannerName];
    if (en != null) return en;
    return _builtIn['en']!['_default']!;
  }

  /// All locale codes with built-in messages.
  static Set<String> get availableLocales => _builtIn.keys.toSet();

  /// All scanner names with built-in English messages.
  static Set<String> get supportedScanners =>
      _builtIn['en']!.keys.where((k) => k != '_default').toSet();

  static const _builtIn = <String, Map<String, String>>{
    'en': _en,
    'es': _es,
    'pt': _pt,
    'fr': _fr,
    'de': _de,
    'it': _it,
    'ja': _ja,
    'ko': _ko,
    'zh': _zh,
    'ar': _ar,
    'hi': _hi,
  };

  // -- English --
  static const _en = <String, String>{
    '_default': 'A safety issue was detected.',
    'pii': 'Personal information was detected and handled.',
    'secret': 'A potential secret or credential was detected.',
    'prompt_injection': 'A potential prompt injection was detected.',
    'invisible_text': 'Hidden or invisible characters were detected.',
    'banned_topic': 'Content about a restricted topic was detected.',
    'banned_pattern': 'Content matching a restricted pattern was detected.',
    'token_limit': 'The input exceeds the maximum allowed length.',
    'repetition': 'Excessive repetition was detected.',
    'url': 'An unsafe or suspicious URL was detected.',
    'language': 'Unexpected language or script was detected.',
    'code_exec': 'Potentially dangerous code was detected.',
    'grounding': 'The output may not be grounded in the source material.',
    'schema': 'The output does not match the required schema.',
    'tool_call': 'A tool call validation issue was detected.',
    'padding_attack': 'A padding or entropy attack was detected.',
    'tool_output': 'Unsafe content was detected in a tool output.',
    'hallucination': 'The output may contain hallucinated content.',
    'fact_check': 'A factual inconsistency was detected.',
    'topic_safety': 'The output strayed from the allowed topic.',
    'json_validator': 'The output is not valid JSON.',
    'html_validator': 'The output contains disallowed HTML.',
    'sql_validator': 'The output contains disallowed SQL.',
    'url_format_validator': 'The output contains an invalid URL format.',
    'range_validator': 'A value is outside the allowed range.',
    'choices_validator': 'The output is not one of the allowed choices.',
    'topic_allowlist': 'The content is outside the allowed topics.',
    'competitor_mention': 'A competitor mention was detected.',
    'bias': 'Potential bias was detected.',
    'politeness': 'The tone does not match the expected register.',
    'reading_level': 'The reading level does not match the target.',
    'embedding_grounding':
        'The output may not be grounded in the source material.',
    'policy_rule': 'A guard policy rule was triggered.',
  };

  // -- Spanish --
  static const _es = <String, String>{
    '_default': 'Se detectó un problema de seguridad.',
    'pii': 'Se detectó información personal y se gestionó.',
    'secret': 'Se detectó un posible secreto o credencial.',
    'prompt_injection': 'Se detectó un posible intento de inyección.',
    'invisible_text': 'Se detectaron caracteres ocultos o invisibles.',
    'banned_topic': 'Se detectó contenido sobre un tema restringido.',
    'banned_pattern': 'Se detectó contenido con un patrón restringido.',
    'token_limit': 'La entrada supera la longitud máxima permitida.',
    'repetition': 'Se detectó repetición excesiva.',
    'url': 'Se detectó una URL insegura o sospechosa.',
    'language': 'Se detectó un idioma o escritura inesperado.',
    'code_exec': 'Se detectó código potencialmente peligroso.',
    'grounding': 'La salida puede no estar fundamentada en el material fuente.',
    'schema': 'La salida no coincide con el esquema requerido.',
    'tool_call': 'Se detectó un problema de validación de herramienta.',
    'padding_attack': 'Se detectó un ataque de relleno o entropía.',
    'tool_output':
        'Se detectó contenido inseguro en la salida de una herramienta.',
    'hallucination': 'La salida puede contener contenido alucinado.',
    'fact_check': 'Se detectó una inconsistencia factual.',
    'topic_safety': 'La salida se desvió del tema permitido.',
    'json_validator': 'La salida no es JSON válido.',
    'html_validator': 'La salida contiene HTML no permitido.',
    'sql_validator': 'La salida contiene SQL no permitido.',
    'url_format_validator': 'La salida contiene un formato de URL no válido.',
    'range_validator': 'Un valor está fuera del rango permitido.',
    'choices_validator': 'La salida no es una de las opciones permitidas.',
    'topic_allowlist': 'El contenido está fuera de los temas permitidos.',
    'competitor_mention': 'Se detectó una mención de competidor.',
    'bias': 'Se detectó un posible sesgo.',
    'politeness': 'El tono no coincide con el registro esperado.',
    'reading_level': 'El nivel de lectura no coincide con el objetivo.',
    'embedding_grounding':
        'La salida puede no estar fundamentada en el material fuente.',
    'policy_rule': 'Se activó una regla de política de guardia.',
  };

  // -- Portuguese --
  static const _pt = <String, String>{
    '_default': 'Um problema de segurança foi detectado.',
    'pii': 'Informação pessoal foi detectada e tratada.',
    'secret': 'Um possível segredo ou credencial foi detectado.',
    'prompt_injection': 'Uma possível injeção de prompt foi detectada.',
    'invisible_text': 'Caracteres ocultos ou invisíveis foram detectados.',
    'banned_topic': 'Conteúdo sobre um tópico restrito foi detectado.',
    'banned_pattern': 'Conteúdo com um padrão restrito foi detectado.',
    'token_limit': 'A entrada excede o comprimento máximo permitido.',
    'repetition': 'Repetição excessiva foi detectada.',
    'url': 'Uma URL insegura ou suspeita foi detectada.',
    'language': 'Idioma ou escrita inesperado foi detectado.',
    'code_exec': 'Código potencialmente perigoso foi detectado.',
    'grounding': 'A saída pode não estar fundamentada no material fonte.',
    'schema': 'A saída não corresponde ao esquema exigido.',
    'tool_call': 'Um problema de validação de ferramenta foi detectado.',
    'padding_attack': 'Um ataque de preenchimento ou entropia foi detectado.',
    'tool_output':
        'Conteúdo inseguro foi detectado na saída de uma ferramenta.',
    'hallucination': 'A saída pode conter conteúdo alucinado.',
    'fact_check': 'Uma inconsistência factual foi detectada.',
    'topic_safety': 'A saída desviou do tópico permitido.',
    'json_validator': 'A saída não é JSON válido.',
    'html_validator': 'A saída contém HTML não permitido.',
    'sql_validator': 'A saída contém SQL não permitido.',
    'url_format_validator': 'A saída contém um formato de URL inválido.',
    'range_validator': 'Um valor está fora do intervalo permitido.',
    'choices_validator': 'A saída não é uma das opções permitidas.',
    'topic_allowlist': 'O conteúdo está fora dos tópicos permitidos.',
    'competitor_mention': 'Uma menção a concorrente foi detectada.',
    'bias': 'Um possível viés foi detectado.',
    'politeness': 'O tom não corresponde ao registro esperado.',
    'reading_level': 'O nível de leitura não corresponde ao objetivo.',
    'embedding_grounding':
        'A saída pode não estar fundamentada no material fonte.',
    'policy_rule': 'Uma regra de política de guarda foi acionada.',
  };

  // -- French --
  static const _fr = <String, String>{
    '_default': 'Un problème de sécurité a été détecté.',
    'pii': 'Des informations personnelles ont été détectées et traitées.',
    'secret': 'Un secret ou identifiant potentiel a été détecté.',
    'prompt_injection': "Une tentative d'injection potentielle a été détectée.",
    'invisible_text': 'Des caractères cachés ou invisibles ont été détectés.',
    'banned_topic': 'Du contenu sur un sujet restreint a été détecté.',
    'banned_pattern':
        'Du contenu correspondant à un motif restreint a été détecté.',
    'token_limit': "L'entrée dépasse la longueur maximale autorisée.",
    'repetition': 'Une répétition excessive a été détectée.',
    'url': 'Une URL non sécurisée ou suspecte a été détectée.',
    'language': 'Une langue ou écriture inattendue a été détectée.',
    'code_exec': 'Du code potentiellement dangereux a été détecté.',
    'grounding':
        'La sortie pourrait ne pas être fondée sur le matériel source.',
    'schema': 'La sortie ne correspond pas au schéma requis.',
    'tool_call': "Un problème de validation d'outil a été détecté.",
    'padding_attack': 'Une attaque par remplissage ou entropie a été détectée.',
    'tool_output':
        "Du contenu non sécurisé a été détecté dans la sortie d'un outil.",
    'hallucination': 'La sortie pourrait contenir du contenu halluciné.',
    'fact_check': 'Une incohérence factuelle a été détectée.',
    'topic_safety': 'La sortie a dévié du sujet autorisé.',
    'json_validator': 'La sortie n\'est pas du JSON valide.',
    'html_validator': 'La sortie contient du HTML non autorisé.',
    'sql_validator': 'La sortie contient du SQL non autorisé.',
    'url_format_validator': "La sortie contient un format d'URL invalide.",
    'range_validator': 'Une valeur est en dehors de la plage autorisée.',
    'choices_validator': "La sortie n'est pas l'un des choix autorisés.",
    'topic_allowlist': 'Le contenu est en dehors des sujets autorisés.',
    'competitor_mention': 'Une mention de concurrent a été détectée.',
    'bias': 'Un biais potentiel a été détecté.',
    'politeness': 'Le ton ne correspond pas au registre attendu.',
    'reading_level': 'Le niveau de lecture ne correspond pas à la cible.',
    'embedding_grounding':
        'La sortie pourrait ne pas être fondée sur le matériel source.',
    'policy_rule': 'Une règle de politique de garde a été déclenchée.',
  };

  // -- German --
  static const _de = <String, String>{
    '_default': 'Ein Sicherheitsproblem wurde erkannt.',
    'pii': 'Persönliche Informationen wurden erkannt und behandelt.',
    'secret': 'Ein mögliches Geheimnis oder Zugangsdaten wurden erkannt.',
    'prompt_injection': 'Ein möglicher Injektionsversuch wurde erkannt.',
    'invisible_text': 'Versteckte oder unsichtbare Zeichen wurden erkannt.',
    'banned_topic': 'Inhalt zu einem eingeschränkten Thema wurde erkannt.',
    'banned_pattern': 'Inhalt mit einem eingeschränkten Muster wurde erkannt.',
    'token_limit': 'Die Eingabe überschreitet die zulässige Maximallänge.',
    'repetition': 'Übermäßige Wiederholung wurde erkannt.',
    'url': 'Eine unsichere oder verdächtige URL wurde erkannt.',
    'language': 'Unerwartete Sprache oder Schrift wurde erkannt.',
    'code_exec': 'Potenziell gefährlicher Code wurde erkannt.',
    'grounding':
        'Die Ausgabe ist möglicherweise nicht im Quellmaterial verankert.',
    'schema': 'Die Ausgabe entspricht nicht dem erforderlichen Schema.',
    'tool_call': 'Ein Tool-Validierungsproblem wurde erkannt.',
    'padding_attack': 'Ein Padding- oder Entropieangriff wurde erkannt.',
    'tool_output': 'Unsicherer Inhalt wurde in einer Tool-Ausgabe erkannt.',
    'hallucination':
        'Die Ausgabe enthält möglicherweise halluzinierte Inhalte.',
    'fact_check': 'Eine faktische Inkonsistenz wurde erkannt.',
    'topic_safety': 'Die Ausgabe ist vom erlaubten Thema abgewichen.',
    'json_validator': 'Die Ausgabe ist kein gültiges JSON.',
    'html_validator': 'Die Ausgabe enthält unerlaubtes HTML.',
    'sql_validator': 'Die Ausgabe enthält unerlaubtes SQL.',
    'url_format_validator': 'Die Ausgabe enthält ein ungültiges URL-Format.',
    'range_validator': 'Ein Wert liegt außerhalb des zulässigen Bereichs.',
    'choices_validator': 'Die Ausgabe ist keine der zulässigen Optionen.',
    'topic_allowlist': 'Der Inhalt liegt außerhalb der erlaubten Themen.',
    'competitor_mention': 'Eine Wettbewerbererwähnung wurde erkannt.',
    'bias': 'Mögliche Voreingenommenheit wurde erkannt.',
    'politeness': 'Der Ton entspricht nicht dem erwarteten Register.',
    'reading_level': 'Das Leseniveau entspricht nicht dem Ziel.',
    'embedding_grounding':
        'Die Ausgabe ist möglicherweise nicht im Quellmaterial verankert.',
    'policy_rule': 'Eine Schutzrichtlinie wurde ausgelöst.',
  };

  // -- Italian --
  static const _it = <String, String>{
    '_default': 'È stato rilevato un problema di sicurezza.',
    'pii': 'Sono state rilevate informazioni personali e gestite.',
    'secret': 'È stato rilevato un possibile segreto o credenziale.',
    'prompt_injection': 'È stato rilevato un possibile tentativo di iniezione.',
    'invisible_text': 'Sono stati rilevati caratteri nascosti o invisibili.',
    'banned_topic': 'È stato rilevato contenuto su un argomento limitato.',
    'banned_pattern': 'È stato rilevato contenuto con un modello limitato.',
    'token_limit': "L'input supera la lunghezza massima consentita.",
    'repetition': 'È stata rilevata una ripetizione eccessiva.',
    'url': 'È stata rilevata una URL non sicura o sospetta.',
    'language': 'È stata rilevata una lingua o scrittura inaspettata.',
    'code_exec': 'È stato rilevato codice potenzialmente pericoloso.',
    'grounding': "L'output potrebbe non essere fondato sul materiale sorgente.",
    'schema': "L'output non corrisponde allo schema richiesto.",
    'tool_call': 'È stato rilevato un problema di validazione dello strumento.',
    'padding_attack': 'È stato rilevato un attacco di riempimento o entropia.',
    'tool_output':
        "È stato rilevato contenuto non sicuro nell'output di uno strumento.",
    'hallucination': "L'output potrebbe contenere contenuto allucinato.",
    'fact_check': "È stata rilevata un'incoerenza fattuale.",
    'topic_safety': "L'output si è allontanato dall'argomento consentito.",
    'json_validator': "L'output non è JSON valido.",
    'html_validator': "L'output contiene HTML non consentito.",
    'sql_validator': "L'output contiene SQL non consentito.",
    'url_format_validator': "L'output contiene un formato URL non valido.",
    'range_validator': "Un valore è al di fuori dell'intervallo consentito.",
    'choices_validator': "L'output non è una delle scelte consentite.",
    'topic_allowlist': 'Il contenuto è al di fuori degli argomenti consentiti.',
    'competitor_mention': 'È stata rilevata una menzione di un concorrente.',
    'bias': 'È stato rilevato un possibile pregiudizio.',
    'politeness': 'Il tono non corrisponde al registro atteso.',
    'reading_level': "Il livello di lettura non corrisponde all'obiettivo.",
    'embedding_grounding':
        "L'output potrebbe non essere fondato sul materiale sorgente.",
    'policy_rule': 'È stata attivata una regola di politica di guardia.',
  };

  // -- Japanese --
  static const _ja = <String, String>{
    '_default': 'セキュリティ上の問題が検出されました。',
    'pii': '個人情報が検出され、処理されました。',
    'secret': '秘密情報または認証情報の可能性が検出されました。',
    'prompt_injection': 'プロンプトインジェクションの可能性が検出されました。',
    'invisible_text': '隠しまたは不可視の文字が検出されました。',
    'banned_topic': '制限されたトピックに関するコンテンツが検出されました。',
    'banned_pattern': '制限されたパターンに一致するコンテンツが検出されました。',
    'token_limit': '入力が許可された最大長を超えています。',
    'repetition': '過度な繰り返しが検出されました。',
    'url': '安全でないまたは疑わしいURLが検出されました。',
    'language': '予期しない言語またはスクリプトが検出されました。',
    'code_exec': '潜在的に危険なコードが検出されました。',
    'grounding': '出力がソース資料に基づいていない可能性があります。',
    'schema': '出力が必要なスキーマと一致しません。',
    'tool_call': 'ツール呼び出しの検証問題が検出されました。',
    'padding_attack': 'パディングまたはエントロピー攻撃が検出されました。',
    'tool_output': 'ツール出力に安全でないコンテンツが検出されました。',
    'hallucination': '出力にハルシネーションが含まれている可能性があります。',
    'fact_check': '事実の不整合が検出されました。',
    'topic_safety': '出力が許可されたトピックから逸脱しました。',
    'json_validator': '出力が有効なJSONではありません。',
    'html_validator': '出力に許可されていないHTMLが含まれています。',
    'sql_validator': '出力に許可されていないSQLが含まれています。',
    'url_format_validator': '出力に無効なURL形式が含まれています。',
    'range_validator': '値が許可された範囲外です。',
    'choices_validator': '出力が許可された選択肢のいずれでもありません。',
    'topic_allowlist': 'コンテンツが許可されたトピック外です。',
    'competitor_mention': '競合他社の言及が検出されました。',
    'bias': 'バイアスの可能性が検出されました。',
    'politeness': 'トーンが期待されるレジスターと一致しません。',
    'reading_level': '読解レベルが目標と一致しません。',
    'embedding_grounding': '出力がソース資料に基づいていない可能性があります。',
    'policy_rule': 'ガードポリシールールが発動されました。',
  };

  // -- Korean --
  static const _ko = <String, String>{
    '_default': '보안 문제가 감지되었습니다.',
    'pii': '개인정보가 감지되어 처리되었습니다.',
    'secret': '잠재적인 비밀 또는 자격 증명이 감지되었습니다.',
    'prompt_injection': '잠재적인 프롬프트 인젝션이 감지되었습니다.',
    'invisible_text': '숨겨진 또는 보이지 않는 문자가 감지되었습니다.',
    'banned_topic': '제한된 주제에 대한 콘텐츠가 감지되었습니다.',
    'banned_pattern': '제한된 패턴과 일치하는 콘텐츠가 감지되었습니다.',
    'token_limit': '입력이 허용된 최대 길이를 초과합니다.',
    'repetition': '과도한 반복이 감지되었습니다.',
    'url': '안전하지 않거나 의심스러운 URL이 감지되었습니다.',
    'language': '예상치 못한 언어 또는 스크립트가 감지되었습니다.',
    'code_exec': '잠재적으로 위험한 코드가 감지되었습니다.',
    'grounding': '출력이 소스 자료에 근거하지 않을 수 있습니다.',
    'schema': '출력이 필요한 스키마와 일치하지 않습니다.',
    'tool_call': '도구 호출 유효성 검사 문제가 감지되었습니다.',
    'padding_attack': '패딩 또는 엔트로피 공격이 감지되었습니다.',
    'tool_output': '도구 출력에서 안전하지 않은 콘텐츠가 감지되었습니다.',
    'hallucination': '출력에 환각 콘텐츠가 포함되어 있을 수 있습니다.',
    'fact_check': '사실적 불일치가 감지되었습니다.',
    'topic_safety': '출력이 허용된 주제에서 벗어났습니다.',
    'json_validator': '출력이 유효한 JSON이 아닙니다.',
    'html_validator': '출력에 허용되지 않은 HTML이 포함되어 있습니다.',
    'sql_validator': '출력에 허용되지 않은 SQL이 포함되어 있습니다.',
    'url_format_validator': '출력에 잘못된 URL 형식이 포함되어 있습니다.',
    'range_validator': '값이 허용된 범위를 벗어났습니다.',
    'choices_validator': '출력이 허용된 선택지 중 하나가 아닙니다.',
    'topic_allowlist': '콘텐츠가 허용된 주제 밖에 있습니다.',
    'competitor_mention': '경쟁사 언급이 감지되었습니다.',
    'bias': '잠재적 편향이 감지되었습니다.',
    'politeness': '어조가 예상 레지스터와 일치하지 않습니다.',
    'reading_level': '독해 수준이 목표와 일치하지 않습니다.',
    'embedding_grounding': '출력이 소스 자료에 근거하지 않을 수 있습니다.',
    'policy_rule': '가드 정책 규칙이 실행되었습니다.',
  };

  // -- Chinese (Simplified) --
  static const _zh = <String, String>{
    '_default': '检测到安全问题。',
    'pii': '检测到个人信息并已处理。',
    'secret': '检测到潜在的密钥或凭据。',
    'prompt_injection': '检测到潜在的提示注入。',
    'invisible_text': '检测到隐藏或不可见字符。',
    'banned_topic': '检测到受限主题的内容。',
    'banned_pattern': '检测到匹配受限模式的内容。',
    'token_limit': '输入超过允许的最大长度。',
    'repetition': '检测到过度重复。',
    'url': '检测到不安全或可疑的URL。',
    'language': '检测到意外的语言或文字。',
    'code_exec': '检测到潜在危险代码。',
    'grounding': '输出可能未基于源材料。',
    'schema': '输出不符合所需的模式。',
    'tool_call': '检测到工具调用验证问题。',
    'padding_attack': '检测到填充或熵攻击。',
    'tool_output': '在工具输出中检测到不安全内容。',
    'hallucination': '输出可能包含幻觉内容。',
    'fact_check': '检测到事实不一致。',
    'topic_safety': '输出偏离了允许的主题。',
    'json_validator': '输出不是有效的JSON。',
    'html_validator': '输出包含不允许的HTML。',
    'sql_validator': '输出包含不允许的SQL。',
    'url_format_validator': '输出包含无效的URL格式。',
    'range_validator': '值超出允许范围。',
    'choices_validator': '输出不是允许的选项之一。',
    'topic_allowlist': '内容超出允许的主题范围。',
    'competitor_mention': '检测到竞争对手提及。',
    'bias': '检测到潜在偏见。',
    'politeness': '语调不符合预期的语域。',
    'reading_level': '阅读水平不符合目标。',
    'embedding_grounding': '输出可能未基于源材料。',
    'policy_rule': '触发了守护策略规则。',
  };

  // -- Arabic --
  static const _ar = <String, String>{
    '_default': 'تم اكتشاف مشكلة أمنية.',
    'pii': 'تم اكتشاف معلومات شخصية ومعالجتها.',
    'secret': 'تم اكتشاف سر أو بيانات اعتماد محتملة.',
    'prompt_injection': 'تم اكتشاف محاولة حقن محتملة.',
    'invisible_text': 'تم اكتشاف أحرف مخفية أو غير مرئية.',
    'banned_topic': 'تم اكتشاف محتوى حول موضوع مقيد.',
    'banned_pattern': 'تم اكتشاف محتوى يطابق نمطاً مقيداً.',
    'token_limit': 'تجاوز الإدخال الحد الأقصى المسموح به.',
    'repetition': 'تم اكتشاف تكرار مفرط.',
    'url': 'تم اكتشاف عنوان URL غير آمن أو مشبوه.',
    'language': 'تم اكتشاف لغة أو نص غير متوقع.',
    'code_exec': 'تم اكتشاف كود خطير محتمل.',
    'grounding': 'قد لا يكون الناتج مستنداً إلى المادة المصدر.',
    'schema': 'لا يتطابق الناتج مع المخطط المطلوب.',
    'tool_call': 'تم اكتشاف مشكلة في التحقق من استدعاء الأداة.',
    'padding_attack': 'تم اكتشاف هجوم حشو أو إنتروبيا.',
    'tool_output': 'تم اكتشاف محتوى غير آمن في ناتج الأداة.',
    'hallucination': 'قد يحتوي الناتج على محتوى مُختلق.',
    'fact_check': 'تم اكتشاف تناقض واقعي.',
    'topic_safety': 'انحرف الناتج عن الموضوع المسموح به.',
    'json_validator': 'الناتج ليس JSON صالحاً.',
    'html_validator': 'يحتوي الناتج على HTML غير مسموح به.',
    'sql_validator': 'يحتوي الناتج على SQL غير مسموح به.',
    'url_format_validator': 'يحتوي الناتج على تنسيق URL غير صالح.',
    'range_validator': 'القيمة خارج النطاق المسموح به.',
    'choices_validator': 'الناتج ليس أحد الخيارات المسموح بها.',
    'topic_allowlist': 'المحتوى خارج المواضيع المسموح بها.',
    'competitor_mention': 'تم اكتشاف ذكر منافس.',
    'bias': 'تم اكتشاف تحيز محتمل.',
    'politeness': 'النبرة لا تتوافق مع السجل المتوقع.',
    'reading_level': 'مستوى القراءة لا يتوافق مع الهدف.',
    'embedding_grounding': 'قد لا يكون الناتج مستنداً إلى المادة المصدر.',
    'policy_rule': 'تم تفعيل قاعدة سياسة الحماية.',
  };

  // -- Hindi --
  static const _hi = <String, String>{
    '_default': 'एक सुरक्षा समस्या पाई गई।',
    'pii': 'व्यक्तिगत जानकारी पाई गई और संभाली गई।',
    'secret': 'एक संभावित रहस्य या प्रमाणपत्र पाया गया।',
    'prompt_injection': 'एक संभावित प्रॉम्प्ट इंजेक्शन पाया गया।',
    'invisible_text': 'छिपे या अदृश्य वर्ण पाए गए।',
    'banned_topic': 'प्रतिबंधित विषय से संबंधित सामग्री पाई गई।',
    'banned_pattern': 'प्रतिबंधित पैटर्न से मेल खाती सामग्री पाई गई।',
    'token_limit': 'इनपुट अनुमत अधिकतम लंबाई से अधिक है।',
    'repetition': 'अत्यधिक दोहराव पाया गया।',
    'url': 'एक असुरक्षित या संदिग्ध URL पाया गया।',
    'language': 'अप्रत्याशित भाषा या लिपि पाई गई।',
    'code_exec': 'संभावित खतरनाक कोड पाया गया।',
    'grounding': 'आउटपुट स्रोत सामग्री पर आधारित नहीं हो सकता है।',
    'schema': 'आउटपुट आवश्यक स्कीमा से मेल नहीं खाता।',
    'tool_call': 'टूल कॉल सत्यापन समस्या पाई गई।',
    'padding_attack': 'पैडिंग या एन्ट्रॉपी हमला पाया गया।',
    'tool_output': 'टूल आउटपुट में असुरक्षित सामग्री पाई गई।',
    'hallucination': 'आउटपुट में भ्रामक सामग्री हो सकती है।',
    'fact_check': 'तथ्यात्मक विसंगति पाई गई।',
    'topic_safety': 'आउटपुट अनुमत विषय से भटक गया।',
    'json_validator': 'आउटपुट मान्य JSON नहीं है।',
    'html_validator': 'आउटपुट में अनुमत नहीं HTML है।',
    'sql_validator': 'आउटपुट में अनुमत नहीं SQL है।',
    'url_format_validator': 'आउटपुट में अमान्य URL प्रारूप है।',
    'range_validator': 'मान अनुमत सीमा से बाहर है।',
    'choices_validator': 'आउटपुट अनुमत विकल्पों में से एक नहीं है।',
    'topic_allowlist': 'सामग्री अनुमत विषयों से बाहर है।',
    'competitor_mention': 'प्रतिस्पर्धी का उल्लेख पाया गया।',
    'bias': 'संभावित पूर्वाग्रह पाया गया।',
    'politeness': 'लहजा अपेक्षित रजिस्टर से मेल नहीं खाता।',
    'reading_level': 'पठन स्तर लक्ष्य से मेल नहीं खाता।',
    'embedding_grounding': 'आउटपुट स्रोत सामग्री पर आधारित नहीं हो सकता है।',
    'policy_rule': 'गार्ड नीति नियम सक्रिय हुआ।',
  };
}

/// Convenience extension for locale-aware messages on [ScanResult].
///
/// ```dart
/// final result = guard.scanInput('...');
/// for (final r in result.where((r) => !r.passed)) {
///   print(r.userMessage(locale: 'ja'));
/// }
/// ```
extension ScanResultMessages on ScanResult {
  /// User-facing message for this scan result in [locale].
  String userMessage(
          {String locale = 'en',
          GuardMessages messages = const GuardMessages()}) =>
      messages.message(scanner, locale: locale);
}
