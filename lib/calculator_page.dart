import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart' as me;

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> with SingleTickerProviderStateMixin {
  bool _isDark = true;
  Color get _bg => _isDark ? const Color(0xFF2F3A45) : const Color(0xFFE9EEF2);
  Color get _button => _isDark ? const Color(0xFF3B4854) : const Color(0xFFF7FAFC);
  Color get _shadowDark => _isDark ? const Color(0xFF1E252C) : const Color(0xFFB7C1CA);
  Color get _shadowLight => _isDark ? const Color(0xFF506272) : const Color(0xFFFFFFFF);
  Color get _text => _isDark ? const Color(0xFFE6EDF3) : const Color(0xFF24313B);
  final Color _accent = const Color(0xFF6DFF6A);

  String _expr = '';
  String _result = '0';
  int _activeTab = 0; // 0: calculator, 1: history, 2: functions
  String? _pressedKey;
  final PageController _pc = PageController(initialPage: 0);
  final List<Map<String, String>> _history = <Map<String, String>>[];
  // half-sheet state
  bool _sheetVisible = false;
  int? _sheetIndex; // 1: history, 2: functions
  late final AnimationController _sheetCtrl;
  late final Animation<Offset> _sheetSlide;

  void _onTap(String v) {
    setState(() {
      if (v == 'C') {
        _expr = '';
        _result = '0';
        return;
      }
      if (v == '⌫') {
        if (_expr.isNotEmpty) {
          _expr = _expr.substring(0, _expr.length - 1);
        }
        return;
      }
      if (v == '=') {
        _evaluate();
        return;
      }
      _expr += v;
    });
  }

  void _evaluate() {
    try {
      if (_expr.trim().isEmpty) {
        _result = '0';
        return;
      }
      // Replace custom symbols to math_expressions compatible ones
      var expression = _expr
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll('–', '-');

      // Convert degrees functions sin(30) -> sin(radians(30)) if suffixed with °
      expression = expression.replaceAllMapped(
        RegExp(r'(sin|cos|tan)\(([^\)]+)\)'),
        (m) {
          final fn = m.group(1)!;
          final inside = m.group(2)!;
          // If user typed like 30° then convert
          if (inside.trim().endsWith('°')) {
            final v = inside.trim().substring(0, inside.trim().length - 1);
            return '$fn((${v})*${math.pi}/180)';
          }
          return m.group(0)!;
        },
      );

      // Normalize log(x) to log(10, x) if user typed single-arg form
      expression = expression.replaceAllMapped(
        RegExp(r'log\(([^,]+)\)'),
        (m) {
          final inside = m.group(1)!.trim();
          // if the captured group itself contains a ')' it's likely nested; fallback to original
          if (inside.contains(')')) return m.group(0)!;
          return 'log(10, $inside)';
        },
      );

      // Auto-balance unmatched parentheses at the end
      final openCount = '('.allMatches(expression).length;
      final closeCount = ')'.allMatches(expression).length;
      if (openCount > closeCount) {
        expression = expression + ')' * (openCount - closeCount);
      }

      final parser = me.Parser();
      final exp = parser.parse(expression);
      final cm = me.ContextModel();
      final val = exp.evaluate(me.EvaluationType.REAL, cm);
      _result = _formatNumber(val);
      // store successful calculation in history
      if (_result != 'Error') {
        _history.add({'expr': _expr, 'res': _result});
      }
    } catch (e) {
      _result = 'Error';
    }
  }

  String _formatNumber(num n) {
    if (n.isInfinite || n.isNaN) return 'Error';
    String s = n.toStringAsFixed(10);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _pc,
              onPageChanged: (i) => setState(() => _activeTab = i),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _calculatorBody(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _historyBody(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _functionsBody(),
                ),
              ],
            ),
            if (_sheetVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: h * 0.5,
                child: SlideTransition(
                  position: _sheetSlide,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, -6)),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _sheetIndex == 1 ? 'History' : 'Functions',
                              style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            GestureDetector(
                              onTap: _closeSheet,
                              child: Icon(Icons.close_rounded, color: _text.withOpacity(0.7)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _sheetIndex == 1 ? _historyList() : _functionsPanel(),
                        ),
                        if (_sheetIndex == 1)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Opacity(
                              opacity: _history.isEmpty ? 0.4 : 1,
                              child: GestureDetector(
                                onTap: _history.isEmpty
                                    ? null
                                    : () => setState(() => _history.clear()),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: _neumorphDecoration(
                                    radius: 20,
                                    background: const Color(0xFFE53935),
                                  ),
                                  child: const Text(
                                    'Clear history',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // removed legacy _buildBody()

  // Calculator main body (existing UI)
  Widget _calculatorBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _modeToggle()),
        const SizedBox(height: 8),
        Expanded(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _expr.isEmpty ? '' : _expr,
                  style: TextStyle(color: _text, fontSize: 24),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 6),
                Text(
                  _result,
                  style: TextStyle(
                    color: _text,
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _result == 'Error' ? '' : (_result == '0' ? '' : '≈'),
                    style: TextStyle(color: _accent, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _middleNavRow(),
        const SizedBox(height: 8),
        _grid(),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _middleNavRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _topNavItem(1, Icons.watch_later_outlined, enabled: _history.isNotEmpty),
          _topNavItem(0, Icons.calculate_outlined),
          _topNavItem(2, Icons.straighten),
        ],
      ),
    );
  }

  // Functions page
  bool _isRad = true; // Rad/Deg visual toggle (evaluation already uses radians)

  Widget _functionsBody() {
    Widget chip(String text, VoidCallback onTap) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: _neumorphDecoration(radius: 20),
            child: Text(text, style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );

    // Build in 3 columns like the screenshot
    List<List<String>> colTexts = [
      ['↩','sin','ln','e^x','|x|'],
      [_isRad ? 'Rad' : 'Deg','cos','log','x^2','π'],
      ['√','tan','1/x','x^y','e'],
    ];
    final handlers = {
      '↩': () { setState(() { _activeTab = 0; }); },
      'Rad': () { setState(() { _isRad = !_isRad; }); },
      'Deg': () { setState(() { _isRad = !_isRad; }); },
      '√': () { _insert('sqrt('); },
      'sin': () { _insert('sin('); },
      'cos': () { _insert('cos('); },
      'tan': () { _insert('tan('); },
      'ln': () { _insert('ln('); },
      'log': () { _insert('log('); },
      '1/x': () { _insert('1/('); },
      'e^x': () { _insert('exp('); },
      'x^2': () { _insert('^2'); },
      'x^y': () { _insert('^'); },
      '|x|': () { _insert('abs('); },
      'π': () { _insert('${math.pi}'); },
      'e': () { _insert('${math.e}'); },
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _modeToggle()),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(3, (col) {
              final items = colTexts[col];
              return Expanded(
                child: Column(
                  children: items.map((t) => chip(t, handlers[t]!)).toList(),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // History page: full-screen list of previous calculations
  Widget _historyBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _modeToggle()),
        const SizedBox(height: 12),
        Expanded(
          child: _history.isEmpty
              ? Center(
                  child: Text(
                    'No calculations yet',
                    style: TextStyle(color: _text.withOpacity(0.6)),
                  ),
                )
              : ListView.separated(
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final it = _history[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: _neumorphDecoration(radius: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it['expr']!, style: TextStyle(color: _text.withOpacity(0.85))),
                                const SizedBox(height: 4),
                                Text('= ${it['res']!}', style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _expr = it['expr']!;
                                _result = it['res']!;
                                _activeTab = 0;
                                _pc.animateToPage(0, duration: const Duration(milliseconds: 220), curve: Curves.easeInOut);
                              });
                            },
                            child: Icon(Icons.north_east, color: _text.withOpacity(0.7)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: _history.isEmpty ? null : () => setState(() => _history.clear()),
            child: Opacity(
              opacity: _history.isEmpty ? 0.4 : 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: _neumorphDecoration(radius: 20),
                child: Text('Clear history', style: TextStyle(color: _text)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _insert(String s) {
    setState(() {
      _expr += s;
      _activeTab = 0; // go back to calculator after picking
    });
  }

  bool _hasValueAtEnd() {
    final t = _expr.trimRight();
    return RegExp(r'(\d|\))$').hasMatch(t);
  }

  void _applyPower(int p) {
    setState(() {
      final t = _expr;
      final m = RegExp(r'^(.*?)(\d+(?:\.\d+)?|\))\s*$').firstMatch(t);
      if (m != null) {
        _expr = '${m.group(1)}(${m.group(2)})^$p';
      } else {
        _expr += '^$p';
      }
      _activeTab = 0;
    });
  }

  void _applyReciprocal() {
    setState(() {
      final t = _expr;
      final m = RegExp(r'^(.*?)(\d+(?:\.\d+)?|\))\s*$').firstMatch(t);
      if (m != null) {
        _expr = '${m.group(1)}1/(${m.group(2)})';
      } else {
        _expr += '1/(';
      }
      _activeTab = 0;
    });
  }

  Widget _modeToggle() {
    return GestureDetector(
      onTap: () => setState(() => _isDark = !_isDark),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: _neumorphDecoration(radius: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wb_sunny_rounded,
              size: 18,
              color: _isDark ? _text.withOpacity(0.6) : _accent,
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.nightlight_round,
              size: 18,
              color: _isDark ? _accent : _text.withOpacity(0.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topNavItem(int index, IconData icon, {bool enabled = true}) {
    final bool active = _activeTab == index;
    final Color bg = active ? _accent.withOpacity(0.18) : _button;
    final Color ic = !enabled
        ? _text.withOpacity(0.3)
        : (active ? _accent : _text.withOpacity(0.85));
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressedKey = 'nav$index') : null,
      onTapCancel: enabled ? () => setState(() => _pressedKey = null) : null,
      onTapUp: enabled ? (_) => setState(() => _pressedKey = null) : null,
      onTap: enabled
          ? () {
              if (_activeTab == 0 && (index == 1 || index == 2)) {
                _openHalfSheet(index);
              } else {
                setState(() => _activeTab = index);
                _pc.animateToPage(index, duration: const Duration(milliseconds: 260), curve: Curves.easeInOut);
              }
            }
          : null,
      child: AnimatedScale(
        scale: _pressedKey == 'nav$index' ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            width: 64,
            height: 40,
            decoration: _neumorphDecoration(radius: 14, background: bg),
            child: Icon(icon, color: ic, size: 22),
          ),
        ),
      ),
    );
  }

  

  Widget _grid() {
    final keys = <String>[
      'C', '(', ')', '÷',
      '7', '8', '9', '×',
      '4', '5', '6', '–',
      '1', '2', '3', '+',
      '0', '.', '⌫', '=',
    ];

    return Expanded(
      child: GridView.builder(
        shrinkWrap: true,
        itemCount: keys.length,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, i) {
          final k = keys[i];
          final isOp = ['÷', '×', '–', '+', '=', '%'].contains(k) || k == 'C' || k == '⌫';
          // background/text overrides for special keys
          Color? bg;
          Color? txt;
          if (k == 'C') {
            bg = const Color(0xFFE53935); // red
          } else if (k == '=') {
            bg = const Color(0xFF22C55E); // green
            txt = Colors.white; // white text for '='
          }

          return _calcButton(
            label: k,
            color: _button,
            isAccent: ['÷', '×', '–', '+', '='].contains(k),
            onTap: () {
              if (k == '%') {
                _onTap('/100'); // interpret percent
              } else if (k == '=') {
                _onTap(k);
              } else if (k == 'C' || k == '⌫') {
                _onTap(k);
              } else if (k == '÷' || k == '×' || k == '–' || k == '+') {
                _onTap(' $k ');
              } else {
                _onTap(k);
              }
            },
            isOperator: isOp,
            backgroundOverride: bg,
            textColorOverride: txt,
          );
        },
      ),
    );
  }

  Widget _calcButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isAccent = false,
    bool isOperator = false,
    Color? backgroundOverride,
    Color? textColorOverride,
  }) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressedKey = label),
      onTapCancel: () => setState(() => _pressedKey = null),
      onTapUp: (_) => setState(() => _pressedKey = null),
      onTap: onTap,
      child: AnimatedScale(
        scale: _pressedKey == label ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 70),
        child: Container(
          decoration: _neumorphDecoration(radius: 30, background: backgroundOverride),
          child: Center(
            child: label == '⌫'
                ? Icon(Icons.backspace_rounded, color: textColorOverride ?? (isAccent ? _accent : _text))
                : Text(
                    label,
                    style: TextStyle(
                      color: textColorOverride ?? (isAccent
                          ? _accent
                          : (isOperator ? _text.withOpacity(0.95) : _text)),
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _neumorphDecoration({double radius = 20, Color? background}) {
    return BoxDecoration(
      color: background ?? _button,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: _shadowDark.withOpacity(0.8),
          offset: const Offset(3, 6),
          blurRadius: 10,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: _shadowLight.withOpacity(0.3),
          offset: const Offset(-3, -4),
          blurRadius: 8,
          spreadRadius: 1,
        ),
        // inner shadow effect using foreground gradient overlay
      ],
    );
  }

  @override
  void dispose() {
    _sheetCtrl.dispose();
    _pc.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _sheetCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _sheetSlide = Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _sheetCtrl, curve: Curves.easeOutCubic));
  }

  void _openHalfSheet(int index) {
    setState(() {
      _sheetIndex = index;
      _sheetVisible = true;
    });
    _sheetCtrl.forward(from: 0);
  }

  void _closeSheet() {
    _sheetCtrl.reverse().then((_) {
      if (mounted) setState(() => _sheetVisible = false);
    });
  }

  // sheet contents reusing existing page bodies
  Widget _historyList() {
    if (_history.isEmpty) {
      return Center(child: Text('No calculations yet', style: TextStyle(color: _text.withOpacity(0.6))));
    }
    return ListView.separated(
      itemCount: _history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final it = _history[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: _neumorphDecoration(radius: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it['expr']!, style: TextStyle(color: _text.withOpacity(0.85))),
                    const SizedBox(height: 4),
                    Text('= ${it['res']!}', style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _expr = it['expr']!;
                    _result = it['res']!;
                    _activeTab = 0;
                  });
                  _closeSheet();
                },
                child: Icon(Icons.north_east, color: _text.withOpacity(0.7)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _functionsPanel() {
    // flat list of labels in reading order, 3 columns
    final labels = <String>[
      '↩', _isRad ? 'Rad' : 'Deg', '√',
      'sin', 'cos', 'tan',
      'ln', 'log', '1/x',
      'e^x', 'x^2', 'x^y',
      '|x|', 'π', 'e',
    ];

    final handlers = <String, VoidCallback>{
      '↩': () { _closeSheet(); },
      'Rad': () { setState(() { _isRad = !_isRad; }); },
      'Deg': () { setState(() { _isRad = !_isRad; }); },
      '√': () { _insert('sqrt('); _closeSheet(); },
      'sin': () { _insert('sin('); _closeSheet(); },
      'cos': () { _insert('cos('); _closeSheet(); },
      'tan': () { _insert('tan('); _closeSheet(); },
      'ln': () { _insert('ln('); _closeSheet(); },
      'log': () { _insert('log(10, '); _closeSheet(); },
      '1/x': () { _applyReciprocal(); _closeSheet(); },
      'e^x': () { _insert('exp('); _closeSheet(); },
      'x^2': () { _applyPower(2); _closeSheet(); },
      'x^y': () { _insert('^('); _closeSheet(); },
      '|x|': () { _insert('abs('); _closeSheet(); },
      'π': () { _insert('${math.pi}'); _closeSheet(); },
      'e': () { _insert('${math.e}'); _closeSheet(); },
    };

    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.9, // wide rounded chips, avoid overlap
      padding: const EdgeInsets.symmetric(horizontal: 4),
      physics: const BouncingScrollPhysics(),
      children: labels.map((text) {
        final onTap = handlers[text] ?? () {};
        return GestureDetector(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: _neumorphDecoration(radius: 18),
            child: Text(
              text,
              style: TextStyle(color: _text, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }).toList(),
    );
  }
}
