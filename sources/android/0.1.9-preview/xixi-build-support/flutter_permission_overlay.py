"""Preserve Android input preferences across transient accessibility reconnects."""


def transform_server_model(text, replace_once):
    text = replace_once(
        text,
        "    // Initial keyboard status is off on mobile\n"
        "    if (isMobile) {\n"
        "      bind.mainSetOption(key: kOptionEnableKeyboard, value: 'N');\n"
        "    }",
        "    // Android's saved input preference survives a UI/process restart.\n"
        "    // Permission availability is reported separately by InputService.\n"
        "    if (isMobile && !isAndroid) {\n"
        "      bind.mainSetOption(key: kOptionEnableKeyboard, value: 'N');\n"
        "    }",
        'preserve Android input preference at model construction',
    )
    text = replace_once(
        text,
        '        if (_inputOk != value) {\n'
        '          bind.mainSetOption(\n'
        '              key: kOptionEnableKeyboard,\n'
        "              value: value ? defaultOptionYes : 'N');\n"
        '        }\n'
        '        _inputOk = value;',
        '        // A temporarily disconnected accessibility service is not a\n'
        '        // request to revoke the saved Android input preference.\n'
        '        if (_inputOk != value && (!isAndroid || value)) {\n'
        '          bind.mainSetOption(\n'
        '              key: kOptionEnableKeyboard,\n'
        "              value: value ? defaultOptionYes : 'N');\n"
        '        }\n'
        '        _inputOk = value;',
        'keep temporary input disconnection separate from persisted permission',
    )
    return text


def apply_flutter_permissions(project, source, replace_once):
    path = source / 'flutter/lib/models/server_model.dart'
    text = transform_server_model(path.read_text(encoding='utf-8'), replace_once)
    path.write_text(text, encoding='utf-8', newline='\n')
    return [path]
