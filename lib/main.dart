import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

void main() {
  runApp(PlankTimerApp());
}

class PlankTimerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '💪 プランクマスター',
      theme: ThemeData(
        primarySwatch: Colors.purple,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Roboto',
      ),
      home: PlankTimerHome(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/settings': (context) => PlanSettingsScreen(),
        '/stats': (context) => StatsScreen(),
        '/manual': (context) => ManualRecordScreen(),
      },
    );
  }
}

class PlankRecord {
  final DateTime date;
  final int duration; // seconds
  final bool isPlanned;

  PlankRecord({required this.date, required this.duration, required this.isPlanned});

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'duration': duration,
    'isPlanned': isPlanned,
  };

  factory PlankRecord.fromJson(Map<String, dynamic> json) => PlankRecord(
    date: DateTime.parse(json['date']),
    duration: json['duration'],
    isPlanned: json['isPlanned'],
  );
}

// シンプルな1週間メニュー
class WeeklyPlan {
  final int sets; // セット数
  final int secondsPerSet; // 1セットあたりの秒数
  final int restSeconds; // セット間の休憩時間
  final String name;
  final String description;
  
  WeeklyPlan({
    required this.sets, 
    required this.secondsPerSet, 
    this.restSeconds = 30,
    required this.name,
    required this.description,
  });
  
  int get totalSeconds => sets * secondsPerSet; // 1日の総実施時間
  
  Map<String, dynamic> toJson() => {
    'sets': sets,
    'secondsPerSet': secondsPerSet,
    'restSeconds': restSeconds,
    'name': name,
    'description': description,
  };
  
  factory WeeklyPlan.fromJson(Map<String, dynamic> json) => WeeklyPlan(
    sets: json['sets'],
    secondsPerSet: json['secondsPerSet'],
    restSeconds: json['restSeconds'] ?? 30,
    name: json['name'],
    description: json['description'],
  );
}

// スケジュール設定
class WorkoutSchedule {
  final String name;
  final String description;
  final List<bool> weekDays; // 0=日曜, 1=月曜, ..., 6=土曜

  WorkoutSchedule({required this.name, required this.description, required this.weekDays});

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'weekDays': weekDays,
  };

  factory WorkoutSchedule.fromJson(Map<String, dynamic> json) => WorkoutSchedule(
    name: json['name'],
    description: json['description'],
    weekDays: (json['weekDays'] as List).cast<bool>(),
  );
}

class PlankTimerHome extends StatefulWidget {
  @override
  _PlankTimerHomeState createState() => _PlankTimerHomeState();
}

class _PlankTimerHomeState extends State<PlankTimerHome> with TickerProviderStateMixin {
  Timer? _timer;
  int _seconds = 0;
  bool _isRunning = false;
  bool _isPaused = false;
  
  // セット管理
  int _currentSet = 1;
  int _totalSetsToday = 3;
  bool _isResting = false;
  int _restSeconds = 0;
  
  // User progress data
  int _level = 1;
  int _exp = 0;
  int _streak = 0;
  List<PlankRecord> _records = [];
  
  // 設定項目
  bool _requireContinuousTime = true;
  int _minimumRecordTime = 10;
  
  // プリセットプラン（1週間メニュー）
  final List<WeeklyPlan> _presetPlans = [
    WeeklyPlan(
      sets: 2, 
      secondsPerSet: 10, 
      name: '🌱 初心者プラン',
      description: '10秒×2セット（まずは慣れることから）'
    ),
    WeeklyPlan(
      sets: 3, 
      secondsPerSet: 20, 
      name: '💪 基礎プラン',
      description: '20秒×3セット（標準的なメニュー）'
    ),
    WeeklyPlan(
      sets: 3, 
      secondsPerSet: 30, 
      name: '🔥 中級プラン',
      description: '30秒×3セット（しっかりトレーニング）'
    ),
    WeeklyPlan(
      sets: 4, 
      secondsPerSet: 45, 
      name: '⚡ 上級プラン',
      description: '45秒×4セット（本格的なワークアウト）'
    ),
  ];
  
  // カスタムプラン
  WeeklyPlan _customPlan = WeeklyPlan(
    sets: 3, 
    secondsPerSet: 30, 
    name: '🎯 カスタムプラン',
    description: 'あなただけのオリジナルメニュー'
  );
  
  // スケジュール選択肢
  final List<WorkoutSchedule> _scheduleOptions = [
    WorkoutSchedule(
      name: '📅 毎日',
      description: '毎日実施（習慣化重視）',
      weekDays: [true, true, true, true, true, true, true], // 毎日
    ),
    WorkoutSchedule(
      name: '💼 平日のみ',
      description: '月〜金曜日（仕事と両立）',
      weekDays: [false, true, true, true, true, true, false], // 月-金
    ),
    WorkoutSchedule(
      name: '⚡ 週3回',
      description: '月・水・金（筋力向上）',
      weekDays: [false, true, false, true, false, true, false], // 月水金
    ),
    WorkoutSchedule(
      name: '🔥 週4回',
      description: '火・木・土・日（高頻度）',
      weekDays: [true, false, true, false, true, false, true], // 火木土日
    ),
  ];
  
  int _selectedPlanIndex = 1; // デフォルトは基礎プラン
  int _selectedScheduleIndex = 2; // デフォルトは週3回
  WorkoutSchedule _customSchedule = WorkoutSchedule(
    name: '🎯 カスタム',
    description: '曜日を自由に選択',
    weekDays: [false, true, false, true, false, true, false],
  );
  
  // Animations
  late AnimationController _pulseController;
  late AnimationController _celebrationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _celebrationAnimation;

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupAnimations();
    _updateCurrentSetInfo();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
    _celebrationController = AnimationController(
      duration: Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _celebrationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _celebrationController, curve: Curves.elasticOut),
    );
    
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _celebrationController.dispose();
    super.dispose();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _level = prefs.getInt('level') ?? 1;
      _exp = prefs.getInt('exp') ?? 0;
      _streak = prefs.getInt('streak') ?? 0;
      _selectedPlanIndex = prefs.getInt('selectedPlanIndex') ?? 1;
      _selectedScheduleIndex = prefs.getInt('selectedScheduleIndex') ?? 2;
      
      _requireContinuousTime = prefs.getBool('requireContinuousTime') ?? true;
      _minimumRecordTime = prefs.getInt('minimumRecordTime') ?? 10;
      
      final recordsJson = prefs.getStringList('records') ?? [];
      _records = recordsJson.map((json) => PlankRecord.fromJson(jsonDecode(json))).toList();
      
      // カスタムプランのロード（修正）
      final customPlanJson = prefs.getString('customPlan');
      if (customPlanJson != null) {
        try {
          _customPlan = WeeklyPlan.fromJson(jsonDecode(customPlanJson));
        } catch (e) {
          print('カスタムプラン読み込みエラー: $e');
          // デフォルト値を使用
        }
      }
      
      // カスタムスケジュールのロード
      final customScheduleJson = prefs.getString('customSchedule');
      if (customScheduleJson != null) {
        try {
          _customSchedule = WorkoutSchedule.fromJson(jsonDecode(customScheduleJson));
        } catch (e) {
          print('カスタムスケジュール読み込みエラー: $e');
        }
      }
      
      _updateStreak();
      _updateCurrentSetInfo();
    });
  }

  void _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('level', _level);
    await prefs.setInt('exp', _exp);
    await prefs.setInt('streak', _streak);
    await prefs.setInt('selectedPlanIndex', _selectedPlanIndex);
    await prefs.setInt('selectedScheduleIndex', _selectedScheduleIndex);
    
    await prefs.setBool('requireContinuousTime', _requireContinuousTime);
    await prefs.setInt('minimumRecordTime', _minimumRecordTime);
    
    final recordsJson = _records.map((record) => jsonEncode(record.toJson())).toList();
    await prefs.setStringList('records', recordsJson);
    
    // カスタムプランの保存（修正）
    await prefs.setString('customPlan', jsonEncode(_customPlan.toJson()));
    
    // カスタムスケジュールの保存
    await prefs.setString('customSchedule', jsonEncode(_customSchedule.toJson()));
  }

  void _updateCurrentSetInfo() {
    final todayPlan = _getCurrentPlan();
    setState(() {
      _totalSetsToday = todayPlan.sets;
      _currentSet = _getTodayCompletedSets() + 1;
    });
  }

  WeeklyPlan _getCurrentPlan() {
    if (_selectedPlanIndex == 4) {
      return _customPlan;
    }
    return _presetPlans[_selectedPlanIndex];
  }

  WorkoutSchedule _getCurrentSchedule() {
    if (_selectedScheduleIndex == 4) {
      return _customSchedule;
    }
    return _scheduleOptions[_selectedScheduleIndex];
  }

  int _getTodayCompletedSets() {
    final today = DateTime.now();
    final todayRecords = _records.where((r) => _isSameDay(r.date, today)).toList();
    final todayPlan = _getCurrentPlan();
    
    // 今日の目標時間以上の記録をカウント
    return todayRecords.where((r) => r.duration >= todayPlan.secondsPerSet - 5).length;
  }

  bool _isTodayScheduled() {
    final today = DateTime.now();
    final weekday = today.weekday % 7; // 0=日曜日, 1=月曜日, ..., 6=土曜日に変換
    final schedule = _getCurrentSchedule();
    return schedule.weekDays[weekday];
  }

  void _updateStreak() {
    if (_records.isEmpty) {
      _streak = 0;
      return;
    }
    
    final today = DateTime.now();
    int streak = 0;
    
    for (int i = 0; i < 30; i++) {
      final checkDate = today.subtract(Duration(days: i));
      final dayRecords = _records.where((r) => _isSameDay(r.date, checkDate)).toList();
      
      if (dayRecords.isNotEmpty) {
        streak = i + 1;
      } else {
        break;
      }
    }
    
    _streak = streak;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _startTimer() {
    if (_isPaused) {
      _isPaused = false;
    } else {
      _seconds = 0;
    }
    
    setState(() {
      _isRunning = true;
      _isResting = false;
    });
    
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _seconds++;
      });
    });
    
    HapticFeedback.lightImpact();
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _isPaused = true;
    });
    HapticFeedback.mediumImpact();
  }

  void _stopTimer() {
    _timer?.cancel();
    
    if (_seconds >= _minimumRecordTime) {
      _recordPlankSet();
    }
    
    setState(() {
      _isRunning = false;
      _isPaused = false;
    });
    
    HapticFeedback.heavyImpact();
    
    // セット完了後の処理
    final todayPlan = _getCurrentPlan();
    if (_currentSet < _totalSetsToday) {
      _startRestPeriod();
    } else {
      _showWorkoutCompleteDialog();
      Timer(Duration(seconds: 3), () {
        if (!_isRunning && !_isPaused) {
          setState(() {
            _seconds = 0;
            _currentSet = 1;
          });
        }
      });
    }
  }

  void _startRestPeriod() {
    final todayPlan = _getCurrentPlan();
    setState(() {
      _isResting = true;
      _restSeconds = todayPlan.restSeconds;
      _currentSet++;
    });
    
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _restSeconds--;
      });
      
      if (_restSeconds <= 0) {
        timer.cancel();
        setState(() {
          _isResting = false;
          _seconds = 0;
        });
        _showNextSetDialog();
      }
    });
  }

  void _showNextSetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('💪 次のセット準備完了！'),
        content: Text('第${_currentSet}セット目を開始しますか？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startTimer();
            },
            child: Text('🚀 開始'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('⏰ 後で'),
          ),
        ],
      ),
    );
  }

  void _cancelTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _isResting = false;
      _seconds = 0;
      _restSeconds = 0;
    });
    HapticFeedback.heavyImpact();
  }

  void _recordPlankSet() {
    final today = DateTime.now();
    final todayPlan = _getCurrentPlan();
    final isPlanned = _isPlannedSession();
    
    final record = PlankRecord(
      date: today,
      duration: _seconds,
      isPlanned: isPlanned,
    );
    
    setState(() {
      _records.add(record);
      _addExp(_seconds);
      _updateStreak();
    });
    
    _saveData();
    _celebrationController.forward().then((_) => _celebrationController.reset());
  }

  bool _isPlannedSession() {
    final todayPlan = _getCurrentPlan();
    return _isTodayScheduled() && _seconds >= todayPlan.secondsPerSet - 5;
  }

  bool _isTodayComplete() {
    final completedSets = _getTodayCompletedSets();
    final todayPlan = _getCurrentPlan();
    return completedSets >= todayPlan.sets;
  }

  int _getCompletedDaysThisWeek() {
    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday % 7));
    int completedDays = 0;
    final schedule = _getCurrentSchedule();
    
    for (int i = 0; i < 7; i++) {
      final checkDate = startOfWeek.add(Duration(days: i));
      if (checkDate.isAfter(today)) break;
      
      final dayRecords = _records.where((r) => _isSameDay(r.date, checkDate)).toList();
      final weekday = checkDate.weekday % 7;
      
      if (schedule.weekDays[weekday] && dayRecords.isNotEmpty) {
        final dayPlan = _getCurrentPlan();
        final completedSets = dayRecords.where((r) => r.duration >= dayPlan.secondsPerSet - 5).length;
        if (completedSets >= dayPlan.sets) {
          completedDays++;
        }
      }
    }
    
    return completedDays;
  }

  void _addExp(int seconds) {
    int expGain = seconds + (_isPlannedSession() ? 10 : 0) + (_streak > 0 ? _streak * 2 : 0);
    _exp += expGain;
    
    int expNeeded = _level * 100;
    while (_exp >= expNeeded) {
      _exp -= expNeeded;
      _level++;
      expNeeded = _level * 100;
    }
  }

  void _showWorkoutCompleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(Icons.celebration, color: Colors.orange, size: 30),
            SizedBox(width: 10),
            Flexible(
              child: Text('🎉 ワークアウト完了！ 💪', 
                         style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('今日の全セット完了しました！'),
            SizedBox(height: 10),
            if (_isPlannedSession())
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('📅 計画通りの実施でボーナス！ ✨', style: TextStyle(color: Colors.green[800])),
              ),
            if (_streak > 1)
              Container(
                margin: EdgeInsets.only(top: 8),
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('🔥 ${_streak}日連続実施中！ 🏆', style: TextStyle(color: Colors.orange[800])),
              ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                children: [
                  Text('💡 プラン強化のヒント', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                  SizedBox(height: 4),
                  Text('慣れてきたら設定画面で秒数やセット数を増やしてみましょう！', 
                       style: TextStyle(fontSize: 12, color: Colors.blue[700])),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('🎯 完了'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildTimerDisplay() {
    final todayPlan = _getCurrentPlan();
    final schedule = _getCurrentSchedule();
    
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isRunning ? _pulseAnimation.value : 1.0,
          child: Column(
            children: [
              // プラン・スケジュール情報表示
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.purple[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      '${todayPlan.name} × ${schedule.name}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple[800]),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '🎯 第${_currentSet}セット / ${_totalSetsToday}セット (目標: ${todayPlan.secondsPerSet}秒)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.purple[800]),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              
              // メインタイマー
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _isRunning 
                      ? [Colors.purple[400]!, Colors.pink[400]!]
                      : _isResting
                        ? [Colors.orange[400]!, Colors.yellow[400]!]
                        : [Colors.grey[300]!, Colors.grey[400]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _isRunning 
                        ? Colors.purple.withOpacity(0.3) 
                        : _isResting
                          ? Colors.orange.withOpacity(0.3)
                          : Colors.grey.withOpacity(0.3),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isResting) ...[
                        Text('😌 休憩中', style: TextStyle(fontSize: 16, color: Colors.white)),
                        SizedBox(height: 8),
                        Text(_formatTime(_restSeconds), style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                      ] else ...[
                        Text(_formatTime(_seconds), style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
                        if (todayPlan.secondsPerSet > 0 && _seconds > 0)
                          Text('${((_seconds / todayPlan.secondsPerSet) * 100).round()}%', 
                               style: TextStyle(fontSize: 14, color: Colors.white70)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlButtons() {
    return Column(
      children: [
        if (_isResting) ...[
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text('☕ セット間休憩', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[800])),
                SizedBox(height: 8),
                Text('次のセットまで ${_restSeconds}秒', style: TextStyle(color: Colors.orange[700])),
              ],
            ),
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (!_isRunning && !_isPaused)
                _buildControlButton(
                  icon: Icons.play_arrow,
                  label: '🚀 スタート',
                  color: Colors.green,
                  onPressed: _startTimer,
                ),
              if (_isRunning)
                _buildControlButton(
                  icon: Icons.pause,
                  label: '⏸️ 一時停止',
                  color: Colors.orange,
                  onPressed: _pauseTimer,
                ),
              if (_isPaused)
                _buildControlButton(
                  icon: Icons.play_arrow,
                  label: '▶️ 再開',
                  color: Colors.green,
                  onPressed: _startTimer,
                ),
              if (_isRunning || _isPaused)
                _buildControlButton(
                  icon: Icons.stop,
                  label: '🛑 セット完了',
                  color: Colors.blue,
                  onPressed: _stopTimer,
                ),
            ],
          ),
          if (_isRunning || _isPaused)
            Padding(
              padding: EdgeInsets.only(top: 12),
              child: _buildControlButton(
                icon: Icons.close,
                label: '❌ 取り消し',
                color: Colors.red,
                onPressed: _cancelTimer,
              ),
            ),
        ],
        
        SizedBox(height: 16),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _requireContinuousTime 
              ? '💡 ${_minimumRecordTime}秒以上継続で記録されます'
              : '💡 合計時間で目標達成を判定します',
            style: TextStyle(fontSize: 12, color: Colors.blue[700]),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        elevation: 5,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          SizedBox(width: 8),
          Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildProgressInfo() {
    final todayPlan = _getCurrentPlan();
    final schedule = _getCurrentSchedule();
    final expNeeded = _level * 100;
    final completedSets = _getTodayCompletedSets();
    final isScheduledToday = _isTodayScheduled();
    
    return Card(
      margin: EdgeInsets.all(16),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatCard('✨ レベル', _level.toString(), Icons.star, Colors.amber),
                _buildStatCard('🔥 連続実施', '${_streak}日', Icons.local_fire_department, Colors.orange),
                _buildStatCard('🏅 総実施', '${_records.length}回', Icons.fitness_center, Colors.purple),
              ],
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🎯 現在の設定', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                  SizedBox(height: 8),
                  Text('プラン: ${todayPlan.name}', 
                       style: TextStyle(color: Colors.blue[700], fontSize: 12)),
                  Text('スケジュール: ${schedule.name}', 
                       style: TextStyle(color: Colors.blue[700], fontSize: 12)),
                  Text('今日: ${todayPlan.secondsPerSet}秒 × ${todayPlan.sets}セット${isScheduledToday ? " (予定日)" : " (追加実施)"}', 
                       style: TextStyle(color: Colors.blue[700])),
                  SizedBox(height: 8),
                  Text('📊 今日の進捗: $completedSets / ${todayPlan.sets} セット', 
                       style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  LinearProgressIndicator(
                    value: completedSets / todayPlan.sets,
                    backgroundColor: Colors.blue[100],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green[400]!),
                  ),
                  SizedBox(height: 8),
                  Text('📈 今週の達成度', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  LinearProgressIndicator(
                    value: _getWeekProgress(),
                    backgroundColor: Colors.blue[100],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[400]!),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('⭐ 経験値', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple[800])),
                  SizedBox(height: 8),
                  Text('💎 ${_exp} / ${expNeeded} EXP', style: TextStyle(color: Colors.purple[700])),
                  SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _exp / expNeeded,
                    backgroundColor: Colors.purple[100],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.purple[400]!),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getWeekProgress() {
    final completedDays = _getCompletedDaysThisWeek();
    final scheduledDays = _getCurrentSchedule().weekDays.where((day) => day).length;
    return scheduledDays > 0 ? completedDays / scheduledDays : 0.0;
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 4),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 12, color: color.withOpacity(0.8))),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentRecords() {
    final recentRecords = _records.reversed.take(5).toList();
    
    if (recentRecords.isEmpty) {
      return Card(
        margin: EdgeInsets.all(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('📝 実施記録がありません\n💪 最初のプランクを始めましょう！', 
                     style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
        ),
      );
    }
    
    return Card(
      margin: EdgeInsets.all(16),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📊 最近の実施記録', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            ...recentRecords.map((record) => _buildRecordItem(record)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordItem(PlankRecord record) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: record.isPlanned ? Colors.green[50] : Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            width: 4,
            color: record.isPlanned ? Colors.green : Colors.blue,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${record.date.month}/${record.date.day} ${record.date.hour}:${record.date.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                record.isPlanned ? '📋 計画実施' : '🎁 追加実施',
                style: TextStyle(
                  color: record.isPlanned ? Colors.green[700] : Colors.blue[700],
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Text(
            _formatTime(record.duration),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('💪 プランクマスター 🏆', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () async {
              final result = await Navigator.pushNamed(context, '/manual');
              if (result == true) {
                _loadData();
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.bar_chart),
            onPressed: () => Navigator.pushNamed(context, '/stats'),
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () async {
              final result = await Navigator.pushNamed(context, '/settings');
              if (result == true) {
                _loadData();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 40),
            AnimatedBuilder(
              animation: _celebrationAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (_celebrationAnimation.value * 0.1),
                  child: _buildTimerDisplay(),
                );
              },
            ),
            SizedBox(height: 40),
            _buildControlButtons(),
            _buildProgressInfo(),
            _buildRecentRecords(),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// 計画設定画面
class PlanSettingsScreen extends StatefulWidget {
  @override
  _PlanSettingsScreenState createState() => _PlanSettingsScreenState();
}

class _PlanSettingsScreenState extends State<PlanSettingsScreen> {
  int _selectedPlanIndex = 1;
  int _selectedScheduleIndex = 2;
  bool _requireContinuousTime = true;
  int _minimumRecordTime = 10;
  
  WeeklyPlan _customPlan = WeeklyPlan(
    sets: 3, 
    secondsPerSet: 30, 
    name: '🎯 カスタムプラン',
    description: 'あなただけのオリジナルメニュー'
  );
  
  WorkoutSchedule _customSchedule = WorkoutSchedule(
    name: '🎯 カスタム',
    description: '曜日を自由に選択',
    weekDays: [false, true, false, true, false, true, false],
  );
  
  final List<WeeklyPlan> _presetPlans = [
    WeeklyPlan(
      sets: 2, 
      secondsPerSet: 10, 
      name: '🌱 初心者プラン',
      description: '10秒×2セット（まずは慣れることから）'
    ),
    WeeklyPlan(
      sets: 3, 
      secondsPerSet: 20, 
      name: '💪 基礎プラン',
      description: '20秒×3セット（標準的なメニュー）'
    ),
    WeeklyPlan(
      sets: 3, 
      secondsPerSet: 30, 
      name: '🔥 中級プラン',
      description: '30秒×3セット（しっかりトレーニング）'
    ),
    WeeklyPlan(
      sets: 4, 
      secondsPerSet: 45, 
      name: '⚡ 上級プラン',
      description: '45秒×4セット（本格的なワークアウト）'
    ),
  ];

  final List<WorkoutSchedule> _scheduleOptions = [
    WorkoutSchedule(
      name: '📅 毎日',
      description: '毎日実施（習慣化重視）',
      weekDays: [true, true, true, true, true, true, true],
    ),
    WorkoutSchedule(
      name: '💼 平日のみ',
      description: '月〜金曜日（仕事と両立）',
      weekDays: [false, true, true, true, true, true, false],
    ),
    WorkoutSchedule(
      name: '⚡ 週3回',
      description: '月・水・金（筋力向上）',
      weekDays: [false, true, false, true, false, true, false],
    ),
    WorkoutSchedule(
      name: '🔥 週4回',
      description: '火・木・土・日（高頻度）',
      weekDays: [true, false, true, false, true, false, true],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  void _loadCurrentSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedPlanIndex = prefs.getInt('selectedPlanIndex') ?? 1;
      _selectedScheduleIndex = prefs.getInt('selectedScheduleIndex') ?? 2;
      _requireContinuousTime = prefs.getBool('requireContinuousTime') ?? true;
      _minimumRecordTime = prefs.getInt('minimumRecordTime') ?? 10;
      
      // カスタムプランのロード
      final customPlanJson = prefs.getString('customPlan');
      if (customPlanJson != null) {
        try {
          _customPlan = WeeklyPlan.fromJson(jsonDecode(customPlanJson));
        } catch (e) {
          print('カスタムプラン読み込みエラー: $e');
        }
      }
      
      // カスタムスケジュールのロード
      final customScheduleJson = prefs.getString('customSchedule');
      if (customScheduleJson != null) {
        try {
          _customSchedule = WorkoutSchedule.fromJson(jsonDecode(customScheduleJson));
        } catch (e) {
          print('カスタムスケジュール読み込みエラー: $e');
        }
      }
    });
  }

  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selectedPlanIndex', _selectedPlanIndex);
    await prefs.setInt('selectedScheduleIndex', _selectedScheduleIndex);
    await prefs.setBool('requireContinuousTime', _requireContinuousTime);
    await prefs.setInt('minimumRecordTime', _minimumRecordTime);
    
    // カスタムプランの保存
    await prefs.setString('customPlan', jsonEncode(_customPlan.toJson()));
    
    // カスタムスケジュールの保存
    await prefs.setString('customSchedule', jsonEncode(_customSchedule.toJson()));
    
    Navigator.pop(context, true);
  }

  Widget _buildPlanCard(int index) {
    final isSelected = _selectedPlanIndex == index;
    final plan = index < 4 ? _presetPlans[index] : _customPlan;
    
    return Card(
      elevation: isSelected ? 8 : 2,
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.purple : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedPlanIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.purple : Colors.black87,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: Colors.purple, size: 24),
                ],
              ),
              SizedBox(height: 8),
              Text(
                plan.description,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '内容: ${plan.secondsPerSet}秒×${plan.sets}セット (休憩${plan.restSeconds}秒)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.purple[700]),
                ),
              ),
              if (index == 4)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: ElevatedButton(
                    onPressed: () => _showCustomPlanEditor(),
                    child: Text('✏️ カスタマイズ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleCard(int index) {
    final isSelected = _selectedScheduleIndex == index;
    final schedule = index < 4 ? _scheduleOptions[index] : _customSchedule;
    final weekDayNames = ['日', '月', '火', '水', '木', '金', '土'];
    final activeDays = schedule.weekDays.asMap().entries
        .where((entry) => entry.value)
        .map((entry) => weekDayNames[entry.key])
        .join('・');
    
    return Card(
      elevation: isSelected ? 8 : 2,
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedScheduleIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      schedule.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.blue : Colors.black87,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: Colors.blue, size: 24),
                ],
              ),
              SizedBox(height: 8),
              Text(
                schedule.description,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '実施曜日: $activeDays',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue[700]),
                ),
              ),
              if (index == 4)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: ElevatedButton(
                    onPressed: () => _showCustomScheduleEditor(),
                    child: Text('✏️ カスタマイズ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⚙️ 詳細設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            SwitchListTile(
              title: Text('⏱️ 継続時間重視'),
              subtitle: Text('一定時間以上の継続を重視 vs 総時間で評価'),
              value: _requireContinuousTime,
              onChanged: (value) => setState(() => _requireContinuousTime = value),
              activeColor: Colors.purple,
            ),
            if (_requireContinuousTime) ...[
              Divider(),
              ListTile(
                title: Text('📝 最低記録時間'),
                subtitle: Slider(
                  value: _minimumRecordTime.toDouble(),
                  min: 5,
                  max: 30,
                  divisions: 25,
                  label: '${_minimumRecordTime}秒',
                  onChanged: (value) => setState(() => _minimumRecordTime = value.round()),
                  activeColor: Colors.purple,
                ),
                trailing: Text('${_minimumRecordTime}秒'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCustomPlanEditor() {
    showDialog(
      context: context,
      builder: (context) => CustomPlanEditorDialog(
        initialPlan: _customPlan,
        onSave: (newPlan) {
          setState(() {
            _customPlan = newPlan;
          });
        },
      ),
    );
  }

  void _showCustomScheduleEditor() {
    showDialog(
      context: context,
      builder: (context) => CustomScheduleEditorDialog(
        initialSchedule: _customSchedule,
        onSave: (newSchedule) {
          setState(() {
            _customSchedule = newSchedule;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlan = _selectedPlanIndex < 4 ? _presetPlans[_selectedPlanIndex] : _customPlan;
    final selectedSchedule = _selectedScheduleIndex < 4 ? _scheduleOptions[_selectedScheduleIndex] : _customSchedule;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('⚙️ プラン設定'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(16),
              children: [
                // プランの組み合わせ例
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📋 現在の設定組み合わせ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800])),
                      SizedBox(height: 8),
                      Text('${selectedPlan.name} × ${selectedSchedule.name}', 
                           style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('実施内容: ${selectedPlan.secondsPerSet}秒×${selectedPlan.sets}セットを週${selectedSchedule.weekDays.where((d) => d).length}回',
                           style: TextStyle(color: Colors.green[700])),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber[200]!),
                        ),
                        child: Text(
                          '💡 1週間メニュー方式: 同じメニューを継続し、慣れたら手動で強度をアップ！',
                          style: TextStyle(fontSize: 12, color: Colors.amber[800]),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                
                // プラン選択
                Text(
                  '🎯 メニュー選択（1週間の内容）',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '各セットの秒数と回数を定義します（同じメニューを継続）',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                SizedBox(height: 16),
                ...List.generate(5, (index) => _buildPlanCard(index)),
                
                SizedBox(height: 24),
                
                // スケジュール選択
                Text(
                  '📅 スケジュール選択（実施頻度）',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '週の中でいつ実施するかを定義します',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                SizedBox(height: 16),
                ...List.generate(5, (index) => _buildScheduleCard(index)),
                
                SizedBox(height: 24),
                _buildSettingsCard(),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  '💾 設定を保存',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// カスタムプラン編集ダイアログ
class CustomPlanEditorDialog extends StatefulWidget {
  final WeeklyPlan initialPlan;
  final Function(WeeklyPlan) onSave;

  CustomPlanEditorDialog({required this.initialPlan, required this.onSave});

  @override
  _CustomPlanEditorDialogState createState() => _CustomPlanEditorDialogState();
}

class _CustomPlanEditorDialogState extends State<CustomPlanEditorDialog> {
  late int _sets;
  late int _secondsPerSet;
  late int _restSeconds;

  @override
  void initState() {
    super.initState();
    _sets = widget.initialPlan.sets;
    _secondsPerSet = widget.initialPlan.secondsPerSet;
    _restSeconds = widget.initialPlan.restSeconds;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: EdgeInsets.all(16),
        constraints: BoxConstraints(maxHeight: 500),
        child: Column(
          children: [
            Text(
              '🎯 カスタムメニュー編集',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              '1週間継続するメニューを設定',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 16),
            
            // プレビュー
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '設定内容: ${_secondsPerSet}秒×${_sets}セット (休憩${_restSeconds}秒)',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple[800]),
              ),
            ),
            SizedBox(height: 16),
            
            Expanded(
              child: Column(
                children: [
                  // セット数
                  ListTile(
                    title: Text('セット数'),
                    subtitle: Slider(
                      value: _sets.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '${_sets}セット',
                      onChanged: (value) => setState(() => _sets = value.round()),
                    ),
                    trailing: Text('${_sets}セット'),
                  ),
                  
                  // 秒数
                  ListTile(
                    title: Text('1セットの秒数'),
                    subtitle: Slider(
                      value: _secondsPerSet.toDouble(),
                      min: 10,
                      max: 300,
                      divisions: 58,
                      label: '${_secondsPerSet}秒',
                      onChanged: (value) => setState(() => _secondsPerSet = value.round()),
                    ),
                    trailing: Text('${_secondsPerSet}秒'),
                  ),
                  
                  // 休憩時間
                  ListTile(
                    title: Text('セット間休憩'),
                    subtitle: Slider(
                      value: _restSeconds.toDouble(),
                      min: 10,
                      max: 120,
                      divisions: 22,
                      label: '${_restSeconds}秒',
                      onChanged: (value) => setState(() => _restSeconds = value.round()),
                    ),
                    trailing: Text('${_restSeconds}秒'),
                  ),
                ],
              ),
            ),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final newPlan = WeeklyPlan(
                      sets: _sets,
                      secondsPerSet: _secondsPerSet,
                      restSeconds: _restSeconds,
                      name: '🎯 カスタムプラン',
                      description: 'あなただけのオリジナルメニュー',
                    );
                    widget.onSave(newPlan);
                    Navigator.pop(context);
                  },
                  child: Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// カスタムスケジュール編集ダイアログ
class CustomScheduleEditorDialog extends StatefulWidget {
  final WorkoutSchedule initialSchedule;
  final Function(WorkoutSchedule) onSave;

  CustomScheduleEditorDialog({required this.initialSchedule, required this.onSave});

  @override
  _CustomScheduleEditorDialogState createState() => _CustomScheduleEditorDialogState();
}

class _CustomScheduleEditorDialogState extends State<CustomScheduleEditorDialog> {
  late List<bool> _weekDays;
  final List<String> _dayNames = ['日曜日', '月曜日', '火曜日', '水曜日', '木曜日', '金曜日', '土曜日'];

  @override
  void initState() {
    super.initState();
    _weekDays = List.from(widget.initialSchedule.weekDays);
  }

  @override
  Widget build(BuildContext context) {
    final activeDaysCount = _weekDays.where((day) => day).length;
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: EdgeInsets.all(16),
        constraints: BoxConstraints(maxHeight: 500),
        child: Column(
          children: [
            Text(
              '📅 カスタムスケジュール編集',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              '実施する曜日を選択してください',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 16),
            
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '週${activeDaysCount}回の実施になります',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800]),
              ),
            ),
            SizedBox(height: 16),
            
            Expanded(
              child: ListView.builder(
                itemCount: 7,
                itemBuilder: (context, index) {
                  return CheckboxListTile(
                    title: Text(_dayNames[index]),
                    value: _weekDays[index],
                    onChanged: (value) {
                      setState(() {
                        _weekDays[index] = value ?? false;
                      });
                    },
                    activeColor: Colors.blue,
                  );
                },
              ),
            ),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: activeDaysCount > 0 ? () {
                    final newSchedule = WorkoutSchedule(
                      name: '🎯 カスタム',
                      description: '週${activeDaysCount}回の実施',
                      weekDays: _weekDays,
                    );
                    widget.onSave(newSchedule);
                    Navigator.pop(context);
                  } : null,
                  child: Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 統計画面
class StatsScreen extends StatefulWidget {
  @override
  _StatsScreenState createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<PlankRecord> _records = [];
  String _selectedPeriod = '7days'; // '7days', '30days', '90days'
  
  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  void _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final recordsJson = prefs.getStringList('records') ?? [];
    setState(() {
      _records = recordsJson.map((json) => PlankRecord.fromJson(jsonDecode(json))).toList();
    });
  }

  List<MapEntry<DateTime, List<PlankRecord>>> _getDataForPeriod(int days) {
    final now = DateTime.now();
    final periodDays = List.generate(days, (index) =>
      DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1 - index)));
    
    return periodDays.map((date) {
      final dayRecords = _records.where((record) => 
        record.date.year == date.year &&
        record.date.month == date.month &&
        record.date.day == date.day
      ).toList();
      return MapEntry(date, dayRecords);
    }).toList();
  }

  List<MapEntry<DateTime, List<PlankRecord>>> _getLast7DaysData() {
    return _getDataForPeriod(7);
  }

  List<MapEntry<DateTime, List<PlankRecord>>> _getLast30DaysData() {
    return _getDataForPeriod(30);
  }

  List<MapEntry<DateTime, List<PlankRecord>>> _getLast90DaysData() {
    return _getDataForPeriod(90);
  }

  List<MapEntry<DateTime, List<PlankRecord>>> _getSelectedPeriodData() {
    switch (_selectedPeriod) {
      case '30days':
        return _getLast30DaysData();
      case '90days':
        return _getLast90DaysData();
      case '7days':
      default:
        return _getLast7DaysData();
    }
  }

  Color _getColorForRecordCount(int count) {
    if (count == 0) return Colors.grey[300]!;
    if (count == 1) return Colors.green[300]!;
    if (count == 2) return Colors.blue[300]!;
    if (count == 3) return Colors.orange[300]!;
    return Colors.purple[300]!; // 4回以上
  }

  Widget _buildPeriodSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: () => setState(() => _selectedPeriod = '7days'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedPeriod == '7days' ? Colors.purple : Colors.grey,
            ),
            child: Text('7日間'),
          ),
          SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => setState(() => _selectedPeriod = '30days'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedPeriod == '30days' ? Colors.purple : Colors.grey,
            ),
            child: Text('30日間'),
          ),
          SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => setState(() => _selectedPeriod = '90days'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedPeriod == '90days' ? Colors.purple : Colors.grey,
            ),
            child: Text('90日間'),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final data = _getSelectedPeriodData();
    final periodTitle = _selectedPeriod == '7days' ? '過去7日間' : _selectedPeriod == '30days' ? '過去30日間' : '過去90日間';
    
    if (data.isEmpty) {
      return Card(
        margin: EdgeInsets.all(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('📊 データがありません', textAlign: TextAlign.center),
        ),
      );
    }
    
    // 全日の合計時間の最大値を計算（表示数値と高さ計算を一致させる）
    final maxTotalDuration = data.map((entry) => 
      entry.value.fold(0, (sum, record) => sum + record.duration)
    ).reduce((a, b) => a > b ? a : b);
    
    if (maxTotalDuration == 0) {
      return Card(
        margin: EdgeInsets.all(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Text('📊 過去7日間の実施時間', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              Text('まだデータがありません', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📊 $periodTitleの実施時間', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('グラフの高さ = その日の合計実施時間', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            SizedBox(height: 16),
            Container(
              height: 200,
              child: Row(
                children: [
                  // Y軸ラベルとメモリ線
                  _buildYAxis(maxTotalDuration),
                  SizedBox(width: 8),
                  // グラフ本体
                  Expanded(
                    child: SingleChildScrollView( // 横スクロールのために追加
                      scrollDirection: Axis.horizontal, // 横スクロールを指定
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: data.map((entry) {
                          final totalDuration = entry.value.fold(0, (sum, record) => sum + record.duration);
                          final height = maxTotalDuration > 0 ? (totalDuration / maxTotalDuration) * 140.0 : 0.0;
                          final barWidth = _getBarWidth(_selectedPeriod); // 期間に応じたバーの幅を取得

                          return Container( // ExpandedをContainerに変更し、幅を指定
                            width: barWidth,
                            padding: EdgeInsets.symmetric(horizontal: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('${totalDuration}s',
                                     style: TextStyle(fontSize: 10),
                                     textAlign: TextAlign.center),
                                SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  height: height.clamp(0.0, 140.0),
                                  decoration: BoxDecoration(
                                    color: _getColorForRecordCount(entry.value.length),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  _formatDateLabel(entry.key, data.indexOf(entry), data, _selectedPeriod),
                                  style: TextStyle(fontSize: _getXAxisLabelFontSize(_selectedPeriod)),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis, // ラベルが長い場合に省略
                                ),
                                if (_selectedPeriod == '7days') // 7日間表示の場合のみ曜日を表示
                                  Text(
                                    ['日', '月', '火', '水', '木', '金', '土'][entry.key.weekday % 7],
                                    style: TextStyle(fontSize: 8, color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateLabel(DateTime date, int index, List<MapEntry<DateTime, List<PlankRecord>>> data, String period) {
    final isFirst = index == 0;
    final isLast = index == data.length - 1;

    if (period == '7days') {
      return '${date.month}/${date.day}'; // 7日間表示は全て月/日
    } else if (period == '30days') {
      // 最初、最後、または5の倍数のインデックス、または月の初日
      if (isFirst || isLast || date.day == 1 || (index % 5 == 0) ) {
        return '${date.month}/${date.day}';
      }
      return ''; // 間引く場合は空文字
    } else if (period == '90days') {
      // 最初、最後、または15の倍数のインデックス、または月の初日
      if (isFirst || isLast || date.day == 1 || (index % 15 == 0)) {
        return '${date.month}/${date.day}';
      }
      return ''; // 間引く場合は空文字
    }
    // デフォルト（ありえないが念のため）
    return '${date.month}/${date.day}';
  }

  // 期間に応じてバーの幅を返すヘルパーメソッド
  double _getBarWidth(String period) {
    if (period == '90days') {
      return 30.0; // 90日表示の場合はバーを細くする
    } else if (period == '30days') {
      return 40.0; // 30日表示
    }
    return 50.0; // 7日表示
  }

  double _getXAxisLabelFontSize(String period) {
    if (period == '90days') {
      return 8.0;
    } else if (period == '30days') {
      return 9.0;
    }
    return 10.0; // 7days
  }

  Widget _buildYAxis(int maxDuration) {
    const double graphDisplayHeight = 140.0; // グラフのバーが表示される実際の高さ
    const int defaultNumberOfLines = 5; // 表示するメモリ線の数（0sを含む）
    int numberOfLines = defaultNumberOfLines;
    int stepSize = 0;

    List<Widget> yAxisItems = [];

    if (maxDuration == 0) {
      // データがない場合でも0sのラベルを表示
      yAxisItems.add(
        Expanded(
          child: Align(
            alignment: Alignment(1.0, 1.0), // 一番下に配置
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('0s', style: TextStyle(fontSize: 8, color: Colors.grey)),
                SizedBox(width: 2),
                Container(width: 4, height: 1, color: Colors.grey[300]),
              ],
            ),
          ),
        ),
      );
      // 他の線は表示しないため、上部にスペーサーを追加して高さを維持
      for (int i = 1; i < numberOfLines; i++) {
        yAxisItems.add(Expanded(child: Container()));
      }
    } else {
      // 最大値に基づいて適切なステップサイズを決定
      if (maxDuration <= 10) {
        stepSize = 2; numberOfLines = (maxDuration / stepSize).ceil() + 1;
      } else if (maxDuration <= 30) {
        stepSize = 5; numberOfLines = (maxDuration / stepSize).ceil() + 1;
      } else if (maxDuration <= 60) {
        stepSize = 10; numberOfLines = (maxDuration / stepSize).ceil() + 1;
      } else if (maxDuration <= 120) {
        stepSize = 20; numberOfLines = (maxDuration / stepSize).ceil() + 1;
      } else if (maxDuration <= 300) {
        stepSize = 50; numberOfLines = (maxDuration / stepSize).ceil() + 1;
      } else if (maxDuration <= 600) {
        stepSize = 100; numberOfLines = (maxDuration / stepSize).ceil() + 1;
      } else {
        stepSize = (maxDuration / (defaultNumberOfLines -1 )).ceil();
        // stepSizeを5の倍数に丸める (例: 23 -> 25, 51 -> 55)
        stepSize = ((stepSize + 4) ~/ 5) * 5;
        numberOfLines = (maxDuration / stepSize).ceil() +1;
        if (numberOfLines < 2) numberOfLines = 2; // 最小でも2本は表示
      }
      if (numberOfLines > 7) numberOfLines = 7; // 最大でも7本程度に抑える

      for (int i = 0; i < numberOfLines; i++) {
        final value = (i * stepSize).round();
        // 最大値を超えるラベルは表示しない（ただし最後の線は最大値に最も近いステップ値とする）
        if (i == numberOfLines -1 && value < maxDuration) {
           // 最後の線は実際のmaxDurationにするか、stepSizeの倍数のままにするか検討
           // ここでは、stepSizeの倍数で、maxDurationを超えない最大のものを表示し、
           // さらにmaxDuration自体も表示するか検討。
           // 今回は、maxDurationに最も近いstepSizeの倍数を表示する。
           // もしmaxDurationがstepSizeの倍数でない場合、最上位の線はmaxDurationそのものを表示する方が良いかもしれない。
           // 以下は、最上位の線はmaxDurationそのものを表示するロジック（ただし、表示位置の調整が必要）
           // final displayValue = (i == numberOfLines - 1) ? maxDuration : value;
           // alignmentの調整も必要になる
        }


        yAxisItems.add(
          Expanded(
            child: Align(
              alignment: Alignment(1.0, (i / (numberOfLines - 1.0)) * 2.0 - 1.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('${value}s', style: TextStyle(fontSize: 8, color: Colors.grey)),
                  SizedBox(width: 2),
                  Container(width: 4, height: 1, color: Colors.grey[300]),
                ],
              ),
            ),
          ),
        );
         if (value >= maxDuration && i < numberOfLines -1) break; // 最大値を超えたら以降のメモリは不要
      }
       // numberOfLinesが動的に変わるため、もしyAxisItemsが少ない場合はスペーサーで埋める
      while(yAxisItems.length < defaultNumberOfLines && yAxisItems.length > 0) {
        yAxisItems.insert(0, Expanded(child: Container())); // 上にスペーサーを追加
      }
      if (yAxisItems.isEmpty && maxDuration > 0) { // 稀なケースだが、計算結果yAxisItemsが空になる場合
         yAxisItems.add(
            Expanded(
              child: Align(
                alignment: Alignment(1.0, 1.0), // 一番下に配置
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('0s', style: TextStyle(fontSize: 8, color: Colors.grey)),
                    SizedBox(width: 2),
                    Container(width: 4, height: 1, color: Colors.grey[300]),
                  ],
                ),
              ),
            ),
          );
          yAxisItems.add(
            Expanded(
              child: Align(
                alignment: Alignment(1.0, -1.0), // 一番上に配置
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('${maxDuration}s', style: TextStyle(fontSize: 8, color: Colors.grey)),
                    SizedBox(width: 2),
                    Container(width: 4, height: 1, color: Colors.grey[300]),
                  ],
                ),
              ),
            ),
          );
          for (int i = 2; i < defaultNumberOfLines; i++) {
             yAxisItems.insert(1, Expanded(child: Container()));
          }
      }
    }


    return Container(
      width: 35,
      height: graphDisplayHeight, // Y軸の描画エリアの高さをグラフのバーの高さに正確に合わせる
      child: Column(
        children: yAxisItems,
      ),
    );
  }

  Widget _buildStatsCards() {
    final totalRecords = _records.length;
    final totalTime = _records.fold(0, (sum, record) => sum + record.duration);
    final avgTime = totalRecords > 0 ? totalTime / totalRecords : 0.0;
    final last7Days = _getLast7DaysData();
    final activeDaysLast7 = last7Days.where((entry) => entry.value.isNotEmpty).length;
    
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildStatCard('📝 総実施回数', '$totalRecords回', Colors.blue)),
              SizedBox(width: 8),
              Expanded(child: _buildStatCard('⏱️ 総実施時間', '${_formatDuration(totalTime)}', Colors.green)),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildStatCard('📈 平均時間', '${avgTime.round()}秒', Colors.orange)),
              SizedBox(width: 8),
              Expanded(child: _buildStatCard('🔥 7日間活動', '$activeDaysLast7日', Colors.red)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600]), textAlign: TextAlign.center),
            SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyTrend() {
    final data = _getLast30DaysData();
    
    if (data.isEmpty) {
      return Card(
        margin: EdgeInsets.all(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('📈 データがありません', textAlign: TextAlign.center),
        ),
      );
    }
    
    final weeklyAverages = <double>[];
    
    for (int i = 0; i < 4; i++) {
      final weekData = data.skip(i * 7).take(7);
      final weekTotal = weekData.fold(0, (sum, entry) => 
        sum + entry.value.fold(0, (daySum, record) => daySum + record.duration));
      weeklyAverages.add(weekTotal / 7);
    }
    
    final maxAvg = weeklyAverages.isEmpty ? 0.0 : weeklyAverages.reduce((a, b) => a > b ? a : b);
    
    if (maxAvg == 0) {
      return Card(
        margin: EdgeInsets.all(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Text('📈 週間平均の推移（過去4週間）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              Text('まだデータがありません', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📈 週間平均の推移（過去4週間）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Container(
              height: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: weeklyAverages.asMap().entries.map((entry) {
                  final height = maxAvg > 0 ? (entry.value / maxAvg) * 100.0 : 0.0;
                  
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${entry.value.round()}s', 
                               style: TextStyle(fontSize: 10),
                               textAlign: TextAlign.center),
                          SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            height: height.clamp(0.0, 100.0),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text('第${entry.key + 1}週', 
                               style: TextStyle(fontSize: 10),
                               textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '${hours}時間${minutes}分';
    } else if (minutes > 0) {
      return '${minutes}分${secs}秒';
    } else {
      return '${secs}秒';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('📊 実施統計'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: _records.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bar_chart, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('📈 まだ実施記録がありません', style: TextStyle(fontSize: 18, color: Colors.grey)),
                Text('💪 プランクを始めて記録を蓄積しましょう！', style: TextStyle(color: Colors.grey)),
              ],
            ),
          )
        : SingleChildScrollView(
            child: Column(
              children: [
                _buildStatsCards(),
                _buildPeriodSelector(), // Added period selector
                _buildChart(), // Changed from _buildWeeklyChart
                _buildMonthlyTrend(),
                SizedBox(height: 20),
              ],
            ),
          ),
    );
  }
}

// 手動記録追加画面
class ManualRecordScreen extends StatefulWidget {
  @override
  _ManualRecordScreenState createState() => _ManualRecordScreenState();
}

class _ManualRecordScreenState extends State<ManualRecordScreen> {
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _duration = 30;
  bool _isPlanned = false;

  void _saveRecord() async {
    final recordDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final record = PlankRecord(
      date: recordDateTime,
      duration: _duration,
      isPlanned: _isPlanned,
    );

    final prefs = await SharedPreferences.getInstance();
    final recordsJson = prefs.getStringList('records') ?? [];
    final records = recordsJson.map((json) => PlankRecord.fromJson(jsonDecode(json))).toList();
    
    records.add(record);
    
    final updatedRecordsJson = records.map((record) => jsonEncode(record.toJson())).toList();
    await prefs.setStringList('records', updatedRecordsJson);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('✅ 記録完了'),
        content: Text('${_duration}秒のプランク記録を追加しました！'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, true);
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('➕ 手動記録追加'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📝 アプリ外で実施したプランクを記録しましょう',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24),
            
            Card(
              child: ListTile(
                leading: Icon(Icons.calendar_today, color: Colors.purple),
                title: Text('実施日'),
                subtitle: Text('${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日'),
                trailing: Icon(Icons.arrow_forward_ios),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now().subtract(Duration(days: 365)),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setState(() => _selectedDate = date);
                  }
                },
              ),
            ),
            SizedBox(height: 12),
            
            Card(
              child: ListTile(
                leading: Icon(Icons.access_time, color: Colors.purple),
                title: Text('実施時刻'),
                subtitle: Text('${_selectedTime.hour}:${_selectedTime.minute.toString().padLeft(2, '0')}'),
                trailing: Icon(Icons.arrow_forward_ios),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _selectedTime,
                  );
                  if (time != null) {
                    setState(() => _selectedTime = time);
                  }
                },
              ),
            ),
            SizedBox(height: 12),
            
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timer, color: Colors.purple),
                        SizedBox(width: 8),
                        Text('実施時間', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    SizedBox(height: 16),
                    Text('${_duration}秒', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.purple)),
                    Slider(
                      value: _duration.toDouble(),
                      min: 5,
                      max: 300,
                      divisions: 59,
                      label: '${_duration}秒',
                      onChanged: (value) => setState(() => _duration = value.round()),
                      activeColor: Colors.purple,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
            
            Card(
              child: SwitchListTile(
                title: Text('📋 計画通りの実施'),
                subtitle: Text('プランに沿った実施の場合はオンにしてください'),
                value: _isPlanned,
                onChanged: (value) => setState(() => _isPlanned = value),
                activeColor: Colors.purple,
                secondary: Icon(Icons.assignment_turned_in, color: Colors.purple),
              ),
            ),
            
            Spacer(),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveRecord,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  '💾 記録を保存',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}