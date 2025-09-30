import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:math_expressions/math_expressions.dart' as me;

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> with TickerProviderStateMixin {
  bool _isDark = true;
  Color get _bg => _isDark ? const Color(0xFF1E2A38) : const Color(0xFFF0F5F9);
  Color get _button => _isDark ? const Color(0xFF2A3A4D) : const Color(0xFFFFFFFF);
  Color get _shadowDark => _isDark ? const Color(0xFF151F2B) : const Color(0xFFB8C7D9);
  Color get _shadowLight => _isDark ? const Color(0xFF3F5168) : const Color(0xFFFFFFFF);
  Color get _text => _isDark ? const Color(0xFFE8F4F8) : const Color(0xFF1A2B3C);
  final Color _accent = const Color(0xFF00E676);
  final Color _errorColor = const Color(0xFFFF5252);

  String _expr = '';
  String _result = '0';
  int _activeTab = 0;
  String? _pressedKey;
  final PageController _pc = PageController(initialPage: 0);
  final List<Map<String, String>> _history = <Map<String, String>>[];
  final TextEditingController _exprCtrl = TextEditingController();
  // Animation controllers
  bool _sheetVisible = false;
  int? _sheetIndex;
  late final AnimationController _sheetCtrl;
  late final Animation<Offset> _sheetSlide;
  late final AnimationController _buttonAnimationCtrl;

  // Calculator state
  bool _isRad = true;
  bool _isError = false;

  // Unit converter state
  final List<String> _unitCategories = const [
    'Area','Length','Temperature','Volume','Mass','Data','Speed','Time','BMI'
  ];
  String _unitCategory = 'Area';
  String _fromUnit = 'm²';
  String _toUnit = 'ft²';
  final TextEditingController _unitInputCtrl = TextEditingController(text: '1');
  String _unitResult = '';
  // BMI inputs
  final TextEditingController _bmiHeightCtrl = TextEditingController(text: '170'); // cm
  final TextEditingController _bmiWeightCtrl = TextEditingController(text: '70');  // kg
  String _bmiActive = 'height'; // 'height' or 'weight'
  final FocusNode _bmiHeightFocus = FocusNode(debugLabel: 'bmiHeight');
  final FocusNode _bmiWeightFocus = FocusNode(debugLabel: 'bmiWeight');
  // Unit converter From field focus
  final FocusNode _unitFromFocus = FocusNode(debugLabel: 'unitFrom');

  @override
  void initState() {
    super.initState();
      _exprCtrl.text = _expr;
  
    // Set system UI overlay style
    _updateSystemUI();
    _loadPrefs();
    
    _sheetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _buttonAnimationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _sheetSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _sheetCtrl,
      curve: Curves.easeOutCubic,
    ));

    // Initialize unit result
    _recomputeUnit();
  }

  

  // Unit keypad (responsive)
  Widget _buildUnitKeypad() {
    final mq = MediaQuery.of(context);
    final isPortrait = mq.orientation == Orientation.portrait;
    final keys = const ['7','8','9','4','5','6','1','2','3','0','.','⌫'];
    final cols = isPortrait ? 3 : 6;
    final rows = (keys.length / cols).ceil();
    final spacing = 12.0;
    final horizontalPadding = 0.0; // parent already has padding
    final keypadHeight = isPortrait ? mq.size.height * 0.38 : mq.size.height * 0.28;
    final itemW = (mq.size.width - horizontalPadding - spacing * (cols - 1)) / cols;
    final itemH = (keypadHeight - spacing * (rows - 1)) / rows;
    final aspect = itemW / itemH;

    return SizedBox(
      height: keypadHeight,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: mq.padding.bottom),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: aspect,
        ),
        itemCount: keys.length,
        itemBuilder: (_, i) {
          final k = keys[i];
          return GestureDetector(
            onTap: () => _onUnitKeyTap(k),
            child: Container(
              decoration: BoxDecoration(
                color: _button,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: _shadowDark, offset: const Offset(2,2), blurRadius: 8),
                  BoxShadow(color: _shadowLight, offset: const Offset(-2,-2), blurRadius: 8),
                ],
              ),
              child: Center(
                child: k == '⌫'
                    ? Icon(Icons.backspace_outlined, color: _text)
                    : Text(k, style: TextStyle(color: _text, fontSize: isPortrait ? 18 : 16, fontWeight: FontWeight.w600)),
              ),
            ),
          );
        },
      ),
    );
  }

  void _onUnitKeyTap(String k) {
    // Route keypad to converter input or BMI active field
    if (_unitCategory == 'BMI') {
      final ctrl = _bmiActive == 'height' ? _bmiHeightCtrl : _bmiWeightCtrl;
      String t = ctrl.text;
      if (k == '⌫') {
        if (t.isNotEmpty) t = t.substring(0, t.length - 1);
      } else if (k == '.') {
        if (!t.contains('.')) t = t.isEmpty ? '0.' : t + '.';
      } else {
        if (t == '0') t = k; else t += k;
      }
      ctrl.text = t.isEmpty ? '0' : t;
      setState((){});
      _savePrefs();
    } else {
      String t = _unitInputCtrl.text;
      if (k == '⌫') {
        if (t.isNotEmpty) t = t.substring(0, t.length - 1);
      } else if (k == '.') {
        if (!t.contains('.')) t = t.isEmpty ? '0.' : t + '.';
      } else {
        if (t == '0') t = k; else t += k;
      }
      _unitInputCtrl.text = t.isEmpty ? '0' : t;
      _recomputeUnit();
      _savePrefs();
    }
  }

  // Return (category label, color)
  (String, Color) _bmiCategory(double bmi) {
    if (bmi < 18.5) return ('Underweight', Colors.orangeAccent);
    if (bmi < 25) return ('Normal weight', _accent);
    if (bmi < 30) return ('Overweight', Colors.amber);
    return ('Obesity', _errorColor);
  }

  // Helper: insert arbitrary text at the caret in the expression field
  void _insertAtCaret(String text) {
    final sel = _exprCtrl.selection;
    String t = _exprCtrl.text;
    if (sel.isValid && sel.start != -1) {
      t = t.replaceRange(sel.start, sel.end, text);
      _exprCtrl.text = t;
      _exprCtrl.selection = TextSelection.collapsed(offset: sel.start + text.length);
    } else {
      _exprCtrl.text = t + text;
      _exprCtrl.selection = TextSelection.collapsed(offset: _exprCtrl.text.length);
    }
    setState(() { _expr = _exprCtrl.text; _isError = false; });
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    // Theme and angle mode
    if (p.containsKey('isDark')) _isDark = p.getBool('isDark') ?? _isDark;
    if (p.containsKey('isRad')) _isRad = p.getBool('isRad') ?? _isRad;
    // History
    final raw = p.getString('history');
    if (raw != null && raw.isNotEmpty) {
      final List list = jsonDecode(raw) as List;
      _history
        ..clear()
        ..addAll(list.cast<Map>().map((e) => {
              'expr': e['expr'] as String,
              'res': e['res'] as String,
            }));
    }
    // Unit converter persisted state
    _unitCategory = p.getString('unitCategory') ?? _unitCategory;
    _fromUnit = p.getString('unitFrom') ?? _fromUnit;
    _toUnit = p.getString('unitTo') ?? _toUnit;
    _unitInputCtrl.text = p.getString('unitInput') ?? _unitInputCtrl.text;
    _bmiHeightCtrl.text = p.getString('bmiHeight') ?? _bmiHeightCtrl.text;
    _bmiWeightCtrl.text = p.getString('bmiWeight') ?? _bmiWeightCtrl.text;
    _recomputeUnit();
    if (mounted) setState(() {});
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('isDark', _isDark);
    await p.setBool('isRad', _isRad);
    await p.setString('history', jsonEncode(_history));
    // Unit converter state
    await p.setString('unitCategory', _unitCategory);
    await p.setString('unitFrom', _fromUnit);
    await p.setString('unitTo', _toUnit);
    await p.setString('unitInput', _unitInputCtrl.text);
    await p.setString('bmiHeight', _bmiHeightCtrl.text);
    await p.setString('bmiWeight', _bmiWeightCtrl.text);
  }

  void _updateSystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: _isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: _isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: _isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  void _onTap(String v) {
    _buttonAnimationCtrl.forward(from: 0);
    
    setState(() {
      _isError = false;
      
      if (v == 'C') {
        _expr = '';
        _exprCtrl.text = '';
        _result = '0';
        return;
      }
      
      if (v == '⌫') {
        final sel = _exprCtrl.selection;
        String t = _exprCtrl.text;
        if (sel.isValid && sel.start != -1) {
          if (sel.start != sel.end) {
            t = t.replaceRange(sel.start, sel.end, '');
            _exprCtrl.text = t;
            _exprCtrl.selection = TextSelection.collapsed(offset: sel.start);
          } else if (sel.start > 0) {
            t = t.replaceRange(sel.start - 1, sel.start, '');
            _exprCtrl.text = t;
            _exprCtrl.selection = TextSelection.collapsed(offset: sel.start - 1);
          }
          _expr = _exprCtrl.text;
        } else if (_expr.isNotEmpty) {
          _expr = _expr.substring(0, _expr.length - 1);
          _exprCtrl.text = _expr;
          _exprCtrl.selection = TextSelection.collapsed(offset: _expr.length);
        }
        return;
      }
      
      if (v == '=') {
        _evaluate();
        return;
      }
      
      // Insert at caret position
      final sel = _exprCtrl.selection;
      String t = _exprCtrl.text;
      final insert = ['+', '–', '×', '÷'].contains(v) ? ' $v ' : v;
      if (sel.isValid && sel.start != -1) {
        t = t.replaceRange(sel.start, sel.end, insert);
        _exprCtrl.text = t;
        final newOffset = sel.start + insert.length;
        _exprCtrl.selection = TextSelection.collapsed(offset: newOffset);
      } else {
        _exprCtrl.text = t + insert;
        _exprCtrl.selection = TextSelection.collapsed(offset: _exprCtrl.text.length);
      }
      _expr = _exprCtrl.text;
    });
  }

  void _evaluate() {
    try {
      if (_expr.trim().isEmpty) {
        _result = '0';
        return;
      }
      
      var expression = _expr
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll('–', '-')
          .replaceAll(' ', ''); // Remove spaces for parsing

      // Percent: transform 50% -> (50/100)
      expression = expression.replaceAllMapped(
        RegExp(r"(\d+(?:\.\d+)?)%"),
        (m) => '(${m.group(1)}/100)');

      // Handle degree conversion if not in radians
      if (!_isRad) {
        expression = expression.replaceAllMapped(
          RegExp(r'(sin|cos|tan)\(([^)]+)\)'),
          (m) {
            final fn = m.group(1)!;
            final inside = m.group(2)!;
            return '$fn(($inside)*${pi}/180)';
          },
        );
      }

      // Handle log functions
      expression = expression.replaceAllMapped(
        RegExp(r'log\(([^,)]+)\)'),
        (m) {
          final inside = m.group(1)!;
          return 'log(10, $inside)';
        },
      );

      // Auto-balance parentheses
      final openCount = '('.allMatches(expression).length;
      final closeCount = ')'.allMatches(expression).length;
      if (openCount > closeCount) {
        expression += ')' * (openCount - closeCount);
      }

      final parser = me.Parser();
      final exp = parser.parse(expression);
      final cm = me.ContextModel();
      final val = exp.evaluate(me.EvaluationType.REAL, cm);
      
      setState(() {
        _result = _formatNumber(val);
        if (_result != 'Error') {
          _history.insert(0, {'expr': _expr, 'res': _result});
          if (_history.length > 50) _history.removeLast();
        } else {
          _isError = true;
        }
      });
      // persist after successful evaluate or error state change
      _savePrefs();
      // After equal, continue from answer
      if (!_isError && _result != 'Error') {
        _expr = _result;
        _exprCtrl.text = _expr;
        _exprCtrl.selection = TextSelection.collapsed(offset: _expr.length);
      }
    } catch (e) {
      setState(() {
        _result = 'Error';
        _isError = true;
      });
      _savePrefs();
    }
  }

  String _formatNumber(num n) {
    if (n.isInfinite || n.isNaN) return 'Error';
    
    // Format large/small numbers with scientific notation
    if (n.abs() > 1e10 || (n.abs() < 1e-10 && n != 0)) {
      return n.toStringAsExponential(6);
    }
    
    String s = n.toStringAsFixed(10);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final padding = mediaQuery.padding;
    
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: _isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: _isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          top: false, // We'll handle the top padding manually for better control
          bottom: false,
          child: Container(
            padding: EdgeInsets.only(
              top: padding.top + 8,
              bottom: padding.bottom + 8,
              left: 16,
              right: 16,
            ),
            child: Stack(
              children: [
                // Main content
                PageView(
                  controller: _pc,
                  onPageChanged: (i) => setState(() => _activeTab = i == 1 ? 3 : 0),
                  physics: const ClampingScrollPhysics(),
                  children: [
                    _buildCalculatorScreen(),
                    _buildUnitConverterScreen(),
                  ],
                ),
                
                // Bottom sheet
                if (_sheetVisible) ...[
                  // Scrim that closes sheet when tapped
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _closeSheet,
                      child: Container(color: Colors.black.withOpacity(0.4)),
                    ),
                  ),
                  // Sheet on top (receives taps normally)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SlideTransition(
                      position: _sheetSlide,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: mediaQuery.size.height * 0.5,
                          decoration: BoxDecoration(
                            color: _bg,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, -5)),
                            ],
                          ),
                          child: _buildSheetContent(),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalculatorScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with theme toggle
        _buildHeader(),
        const SizedBox(height: 20),
        
        // Display area
        Expanded(
          flex: 2,
          child: _buildDisplay(),
        ),
        
        // Navigation
        _buildNavigationBar(),
        const SizedBox(height: 16),
        
        // Calculator grid
        Expanded(
          flex: 5,
          child: _buildCalculatorGrid(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Calculator',
          style: TextStyle(
            color: _text,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        _buildThemeToggle(),
      ],
    );
  }

  Widget _buildThemeToggle() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isDark = !_isDark;
          _updateSystemUI();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _button,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _shadowDark,
              offset: const Offset(2, 2),
              blurRadius: 8,
            ),
            BoxShadow(
              color: _shadowLight,
              offset: const Offset(-2, -2),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(
          _isDark ? Icons.light_mode : Icons.dark_mode,
          color: _accent,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _button,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _shadowDark,
            offset: const Offset(4, 4),
            blurRadius: 12,
          ),
          BoxShadow(
            color: _shadowLight,
            offset: const Offset(-4, -4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Expression
          SizedBox(
            height: 32,
            child: TextField(
              controller: _exprCtrl,
              readOnly: true, // editing only via calculator keys
              showCursor: true,
              enableInteractiveSelection: true, // allow caret placement by tap
              maxLines: 1,
              style: TextStyle(color: _text.withOpacity(0.85), fontSize: 20),
              cursorColor: _accent,
              decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true, contentPadding: EdgeInsets.zero),
            ),
          ),
          const SizedBox(height: 8),
          
          // Result
          SizedBox(
            height: 42,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Text(
                _result,
                style: TextStyle(
                  color: _isError ? _errorColor : _accent,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: _button,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _shadowDark,
            offset: const Offset(2, 2),
            blurRadius: 8,
          ),
          BoxShadow(
            color: _shadowLight,
            offset: const Offset(-2, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.calculate, 'Calculator'),
          _buildNavItem(1, Icons.history, 'History'),
          _buildNavItem(2, Icons.functions, 'Functions'),
          _buildNavItem(3, Icons.swap_horiz, 'Unit'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isActive = _activeTab == index;
    
    return GestureDetector(
      onTap: () {
        if (index == 1 || index == 2) {
          _openHalfSheet(index);
        } else if (index == 3) {
          setState(() {
            _activeTab = 3;
            // Default category when entering Unit: Area
            _unitCategory = 'Area';
            _resetUnitsForCategory();
            _recomputeUnit();
          });
          _pc.animateToPage(
            1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        } else {
          setState(() => _activeTab = 0);
          _pc.animateToPage(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive ? _accent.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: isActive ? _accent : _text.withOpacity(0.7),
          size: 20,
        ),
      ),
    );
  }
  
  // ===================== Unit Converter =====================
  Widget _buildUnitConverterScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Unit Converter', style: TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.w700)),
            _buildThemeToggle(),
          ],
        ),
        const SizedBox(height: 16),
        // Categories
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _unitCategories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final c = _unitCategories[i];
              final selected = c == _unitCategory;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _unitCategory = c;
                    _resetUnitsForCategory();
                    _recomputeUnit();
                    _savePrefs();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? _accent : _button,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: _shadowDark, offset: const Offset(2,2), blurRadius: 8),
                      BoxShadow(color: _shadowLight, offset: const Offset(-2,-2), blurRadius: 8),
                    ],
                  ),
                  child: Text(c, style: TextStyle(color: selected ? Colors.white : _text, fontWeight: FontWeight.w600)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _button, borderRadius: BorderRadius.circular(16), boxShadow: [
              BoxShadow(color: _shadowDark, offset: const Offset(2,2), blurRadius: 8),
              BoxShadow(color: _shadowLight, offset: const Offset(-2,-2), blurRadius: 8),
            ]),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: _unitCategory == 'BMI' ? _buildBmiPane() : _buildUnitPane(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildUnitKeypad(),
      ],
    );
  }

  Widget _buildUnitPane() {
    final units = _unitsForCategory(_unitCategory);
    if (!units.contains(_fromUnit)) _fromUnit = units.first;
    if (!units.contains(_toUnit)) _toUnit = units.length>1 ? units[1] : units.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _unitRow('From', _unitInputCtrl, _fromUnit, units, (u){ setState(() { _fromUnit = u; _recomputeUnit(); _savePrefs(); }); }, focus: _unitFromFocus),
        const SizedBox(height: 12),
        _unitRow('To', null, _toUnit, units, (u){ setState(() { _toUnit = u; _recomputeUnit(); _savePrefs(); }); }),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Text(_unitResult, style: TextStyle(color: _accent, fontSize: 28, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _unitRow(String label, TextEditingController? ctrl, String selUnit, List<String> units, ValueChanged<String> onUnitChanged, {FocusNode? focus}){
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: _text.withOpacity(0.7))),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
                child: ctrl != null
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          focus?.requestFocus();
                          ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
                        },
                        child: TextField(
                          controller: ctrl,
                          focusNode: focus,
                          readOnly: true,
                          showCursor: (focus?.hasFocus ?? false),
                          enableInteractiveSelection: false,
                          cursorColor: _accent,
                          decoration: const InputDecoration(border: InputBorder.none, hintText: 'Enter value'),
                          style: TextStyle(color: _text, fontSize: 18),
                        ),
                      )
                    : Text(_unitResult, style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
          child: DropdownButton<String>(
            value: selUnit,
            dropdownColor: _bg,
            underline: const SizedBox.shrink(),
            iconEnabledColor: _text,
            items: units.map((u)=>DropdownMenuItem(value:u, child: Text(u, style: TextStyle(color:_text)))).toList(),
            onChanged: (v){ if (v!=null) onUnitChanged(v); },
          ),
        )
      ],
    );
  }

  Widget _buildBmiPane(){
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Height (cm)', style: TextStyle(color: _text.withOpacity(0.7))),
        const SizedBox(height: 6),
        _boxedField(_bmiHeightCtrl, _bmiHeightFocus, 'height'),
        const SizedBox(height: 12),
        Text('Weight (kg)', style: TextStyle(color: _text.withOpacity(0.7))),
        const SizedBox(height: 6),
        _boxedField(_bmiWeightCtrl, _bmiWeightFocus, 'weight'),
        const SizedBox(height: 12),
        Builder(builder: (_){
          final h = double.tryParse(_bmiHeightCtrl.text) ?? 0;
          final w = double.tryParse(_bmiWeightCtrl.text) ?? 0;
          final bmi = (h>0) ? w / ((h/100)*(h/100)) : 0.0;
          if (bmi == 0) return const SizedBox.shrink();
          final cat = _bmiCategory(bmi);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BMI: '+bmi.toStringAsFixed(2), style: TextStyle(color: _accent, fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(cat.$1, style: TextStyle(color: cat.$2, fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          );
        })
      ],
    );
  }

  Widget _boxedField(TextEditingController ctrl, FocusNode focus, String name){
    final active = _bmiActive == name;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _bmiActive = name);
        focus.requestFocus();
        // move caret to end
        ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
      },
      onTapDown: (_) {
        // ensure focus and visual state update immediately on first tap
        setState(() => _bmiActive = name);
        focus.requestFocus();
        ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? _accent : Colors.transparent, width: 2.0),
        ),
        child: TextField(
          controller: ctrl,
          focusNode: focus,
          readOnly: true,
          showCursor: active,
          enableInteractiveSelection: false,
          cursorColor: _accent,
          decoration: const InputDecoration(border: InputBorder.none),
          style: TextStyle(color: _text, fontSize: 18),
        ),
      ),
    );
  }

  List<String> _unitsForCategory(String cat){
    switch(cat){
      case 'Area':
        return ['m²','km²','cm²','ft²','yd²','mi²','acre','hectare'];
      case 'Length':
        return ['mm','cm','m','km','in','ft','yd','mi','nmi'];
      case 'Temperature':
        return ['°C','°F','K'];
      case 'Volume':
        return ['mL','L','cm³','m³','ft³','gal','qt','pt','cup','fl oz'];
      case 'Mass':
        return ['mg','g','kg','t','lb','oz','st'];
      case 'Data':
        return ['b','B','KB','MB','GB','TB','PB'];
      case 'Speed':
        return ['m/s','km/h','mph','kn'];
      case 'Time':
        return ['µs','ms','s','min','h','day','week','month','year'];
      default:
        return [];
    }
  }

  void _resetUnitsForCategory(){
    final units = _unitsForCategory(_unitCategory);
    if (units.isNotEmpty){
      _fromUnit = units.first;
      _toUnit = units.length>1 ? units[1] : units.first;
    }
  }

  void _recomputeUnit(){
    if (_unitCategory == 'BMI') { setState((){}); return; }
    final input = double.tryParse(_unitInputCtrl.text) ?? 0.0;
    final out = _convertValue(_unitCategory, input, _fromUnit, _toUnit);
    setState(() {
      _unitResult = out.toStringAsFixed(6)
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');
    });
  }

  double _convertValue(String cat, double v, String from, String to){
    if (from == to) return v;
    if (cat == 'Temperature'){
      double k;
      switch(from){
        case '°C': k = v + 273.15; break;
        case '°F': k = (v - 32) * 5/9 + 273.15; break;
        case 'K': k = v; break;
        default: k = v;
      }
      switch(to){
        case '°C': return k - 273.15;
        case '°F': return (k - 273.15) * 9/5 + 32;
        case 'K': return k;
      }
    }
    if (cat == 'Data'){
      final bytesFactor = {
        'B': 1.0,
        'KB': 1024.0,
        'MB': 1024.0*1024,
        'GB': 1024.0*1024*1024,
        'TB': 1024.0*1024*1024*1024,
        'PB': 1024.0*1024*1024*1024*1024,
      };
      double bytes = from == 'b' ? v/8.0 : v * (bytesFactor[from] ?? 1.0);
      return to == 'b' ? bytes*8.0 : bytes / (bytesFactor[to] ?? 1.0);
    }
    if (cat == 'Speed'){
      final toMS = {'m/s':1.0,'km/h':1000/3600,'mph':1609.344/3600,'kn':1852/3600};
      return v * (toMS[from]!) / (toMS[to]!);
    }
    if (cat == 'Time'){
      final toS = {
        'µs':1e-6,'ms':1e-3,'s':1.0,'min':60.0,'h':3600.0,'day':86400.0,
        'week':604800.0,'month':2629746.0,'year':31557600.0,
      };
      return v * (toS[from]!) / (toS[to]!);
    }
    if (cat == 'Length'){
      final toM = {'mm':0.001,'cm':0.01,'m':1.0,'km':1000.0,'in':0.0254,'ft':0.3048,'yd':0.9144,'mi':1609.344,'nmi':1852.0};
      return v * (toM[from]!) / (toM[to]!);
    }
    if (cat == 'Area'){
      final toM2 = {
        'cm²':0.0001,'m²':1.0,'km²':1e6,'ft²':0.09290304,'yd²':0.83612736,
        'mi²':2589988.110336,'acre':4046.8564224,'hectare':10000.0
      };
      return v * (toM2[from]!) / (toM2[to]!);
    }
    if (cat == 'Volume'){
      final toL = {
        'mL':0.001,'L':1.0,'cm³':0.001,'m³':1000.0,'ft³':28.316846592,
        'gal':3.785411784,'qt':0.946352946,'pt':0.473176473,'cup':0.24,'fl oz':0.0295735295625
      };
      return v * (toL[from]!) / (toL[to]!);
    }
    if (cat == 'Mass'){
      final toKg = {'mg':1e-6,'g':0.001,'kg':1.0,'t':1000.0,'lb':0.45359237,'oz':0.028349523125,'st':6.35029318};
      return v * (toKg[from]!) / (toKg[to]!);
    }
    return v;
  }

  Widget _buildCalculatorGrid() {
    final keys = [
      ['C', '(', ')', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '–'],
      ['1', '2', '3', '+'],
      ['0', '.', '⌫', '='],
    ];

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 20,
      itemBuilder: (context, index) {
        final row = index ~/ 4;
        final col = index % 4;
        final key = keys[row][col];
        
        final isNumber = RegExp(r'[0-9.]').hasMatch(key);
        final isOperator = ['÷', '×', '–', '+', '='].contains(key);
        final isSpecial = ['C', '(', ')', '%'].contains(key);
        
        Color? backgroundColor;
        Color textColor = _text;
        
        if (key == 'C') {
          backgroundColor = _errorColor;
          textColor = Colors.white;
        } else if (key == '=') {
          backgroundColor = _accent;
          textColor = Colors.white;
        } else if (isOperator) {
          textColor = _accent;
        }
        
        final onLongPress = key == '÷' ? () => _onTap('%') : null;
        return _buildCalculatorButton(
          key: key,
          backgroundColor: backgroundColor,
          textColor: textColor,
          isNumber: isNumber,
          onLongPress: onLongPress,
        );
      },
    );
  }

  Widget _buildCalculatorButton({
    required String key,
    Color? backgroundColor,
    Color? textColor,
    required bool isNumber,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: () => _onTap(key),
      onLongPress: onLongPress,
      child: AnimatedBuilder(
        animation: _buttonAnimationCtrl,
        builder: (context, child) {
          final scale = 1.0 - (_buttonAnimationCtrl.value * 0.1);
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: backgroundColor ?? _button,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _shadowDark,
                    offset: const Offset(2, 2),
                    blurRadius: 8,
                  ),
                  BoxShadow(
                    color: _shadowLight,
                    offset: const Offset(-2, -2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Center(
                child: key == '⌫'
                    ? Icon(Icons.backspace_outlined, color: textColor ?? _text)
                    : Text(
                        key,
                        style: TextStyle(
                          color: textColor ?? _text,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            if (key == '÷')
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '%',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }


  Widget _buildHistoryItem(Map<String, String> item, int index) {
    return Card(
      color: _button,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          item['expr']!,
          style: TextStyle(
            color: _text.withOpacity(0.8),
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          '= ${item['res']!}',
          style: TextStyle(
            color: _accent,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: () {
          // Insert history result at caret (append to current expression)
          final value = item['res'] ?? '';
          if (value.isEmpty) return;
          _insertAtCaret(value);
          // switch to calculator page
          _activeTab = 0;
          _pc.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        },
        trailing: IconButton(
          icon: Icon(Icons.replay, color: _accent),
          onPressed: () {
            setState(() {
              _expr = item['expr']!;
              _exprCtrl.text = _expr;
              _exprCtrl.selection = TextSelection.collapsed(offset: _expr.length);
              _result = item['res']!;
              _activeTab = 0;
            });
            _pc.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
          },
        ),
      ),
    );
  }
 

  Widget _buildAngleToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _button,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _shadowDark,
            offset: const Offset(2, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAngleOption('Rad', true),
          _buildAngleOption('Deg', false),
        ],
      ),
    );
  }

  Widget _buildAngleOption(String label, bool isRad) {
    final isSelected = _isRad == isRad;
    
    return GestureDetector(
      onTap: () {
        setState(() => _isRad = isRad);
        _savePrefs();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _accent : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : _text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildFunctionButton(String func) {
    return GestureDetector(
      onTap: () => _insertFunction(func),
      child: Container(
        decoration: BoxDecoration(
          color: _button,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _shadowDark,
              offset: const Offset(2, 2),
              blurRadius: 8,
            ),
            BoxShadow(
              color: _shadowLight,
              offset: const Offset(-2, -2),
              blurRadius: 8,
            ),
          ],
        ),
        child: Center(
          child: Text(
            func,
            style: TextStyle(
              color: _accent,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _insertFunction(String func) {
    String expression = '';
    // Map button label to insertion text
    switch (func) {
      case 'sin':
      case 'cos':
      case 'tan':
        expression = '$func(';
        break;
      case 'log':
        expression = 'log(';
        break;
      case 'ln':
        expression = 'ln(';
        break;
      case '√':
        expression = 'sqrt(';
        break;
      case 'π':
        expression = pi.toString();
        break;
      case 'e':
        expression = e.toString();
        break;
      case 'x²':
        expression = '^2';
        break;
      case 'x^y':
        expression = '^';
        break;
      case '1/x':
        expression = '1/(';
        // close later: we'll wrap selection via caret usage;
        break;
      case '|x|':
        expression = 'abs(';
        break;
    }
    // Insert at caret, then go back to calculator and close the sheet
    _insertAtCaret(expression);
    _activeTab = 0;
    _pc.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    _closeSheet();
  }

  Widget _buildSheetContent() {
    if (_sheetIndex == 1) {
      return _buildHistorySheet();
    } else if (_sheetIndex == 2) {
      return _buildFunctionsSheet();
    } else {
      return const SizedBox.shrink();
    }
  }

  // Bottom-sheet: History list
  Widget _buildHistorySheet() {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'History',
                style: TextStyle(
                  color: _text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: _text),
                onPressed: _closeSheet,
              ),
            ],
          ),
        ),

        Expanded(
          child: _history.isEmpty
              ? Center(
                  child: Text(
                    'No calculations yet',
                    style: TextStyle(color: _text.withOpacity(0.5)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    return _buildHistoryItem(_history[index], index);
                  },
                ),
        ),

        // Clear history button
        if (_history.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _errorColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () {
                setState(() => _history.clear());
                _savePrefs();
                _closeSheet();
              },
              child: const Text('Clear History'),
            ),
          ),
      ],
    );
  }

  Widget _buildFunctionsSheet() {
    // Header
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Functions', style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w700)),
          IconButton(onPressed: _closeSheet, icon: Icon(Icons.close, color: _text)),
        ],
      ),
    );

    // Angle toggle
    final angle = Center(child: _buildAngleToggle());

    // 15 fixed items grid (3x5) without scrolling
    final grid = Expanded(
      child: LayoutBuilder(
        builder: (context, c) {
          const cols = 3;
          const spacing = 12.0;
          final totalH = c.maxHeight;
          final totalW = c.maxWidth - 8;

          final labels = <String>[
            'sin', 'cos', 'tan',
            'log', 'ln', '√',
            'π', 'e', 'x²',
            'x^y', '1/x', '|x|',
          ];

          final rows = ((labels.length + cols - 1) ~/ cols);
          final itemH = (totalH - spacing * (rows - 1)) / rows;
          final itemW = (totalW - spacing * (cols - 1)) / cols;
          final aspect = itemW / (itemH * 0.96);

          return GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: labels.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: aspect,
            ),
            itemBuilder: (_, i) {
              final text = labels[i];
              return GestureDetector(
                onTap: () => _insertFunction(text),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _button,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: _shadowDark, offset: const Offset(2, 2), blurRadius: 8),
                      BoxShadow(color: _shadowLight, offset: const Offset(-2, -2), blurRadius: 8),
                    ],
                  ),
                  child: Text(text, style: TextStyle(color: _accent, fontWeight: FontWeight.w600)),
                ),
              );
            },
          );
        },
      ),
    );

    return Column(children: [header, angle, const SizedBox(height: 8), grid]);
  }

  void _openHalfSheet(int index) {
    setState(() {
      _sheetIndex = index;
      _sheetVisible = true;
    });
    _sheetCtrl.forward();
  }

  void _closeSheet() {
    _sheetCtrl.reverse().then((_) {
      if (mounted) {
        setState(() => _sheetVisible = false);
      }
    });
  }

  @override
  void dispose() {
    _sheetCtrl.dispose();
    _buttonAnimationCtrl.dispose();
    _pc.dispose();
    // Unit converter disposals
    _unitInputCtrl.dispose();
    _bmiHeightCtrl.dispose();
    _bmiWeightCtrl.dispose();
    _bmiHeightFocus.dispose();
    _bmiWeightFocus.dispose();
    _unitFromFocus.dispose();
    super.dispose();
  }
}

// Constants for mathematical values
const double pi = 3.141592653589793;
const double e = 2.718281828459045;