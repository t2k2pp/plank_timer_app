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
        '/manual_add': (context) => ManualAddScreen(),
      },
    );
  }
}

// 手動記録追加画面
class ManualAddScreen extends StatefulWidget {
  @override
  _ManualAddScreenState createState() => _ManualAddScreenState();
}

class _ManualAddScreenState extends State<ManualAddScreen> {
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _duration = 30; // デフォルト30秒
  bool _isPlanned = false;
  String _memo = '';
  bool _isLoading = false;

  final _memoController = TextEditingController();

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.purple,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.purple,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _saveRecord() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 選択した日時を組み合わせ
      final recordDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      // 新しい記録を作成
      final newRecord = PlankRecord(
        date: recordDateTime,
        duration: _duration,
        isPlanned: _isPlanned,
        memo: _memo,
      );

      // 既存の記録を読み込み
      final prefs = await SharedPreferences.getInstance();
      final recordsJson = prefs.getStringList('records') ?? [];
      final records = recordsJson.map((json) => PlankRecord.fromJson(jsonDecode(json))).toList();

      // 新しい記録を追加
      records.add(newRecord);

      // 日時順にソート
      records.sort((a, b) => a.date.compareTo(b.date));

      // 保存
      final updatedRecordsJson = records.map((record) => jsonEncode(record.toJson())).toList();
      await prefs.setStringList('records', updatedRecordsJson);

      // 経験値とレベルの更新
      await _updateExpAndLevel();

      // 成功メッセージを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 記録を追加しました！'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 記録の追加に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateExpAndLevel() async {
    final prefs = await SharedPreferences.getInstance();
    int currentExp = prefs.getInt('exp') ?? 0;
    int currentLevel = prefs.getInt('level') ?? 1;

    // 経験値計算
    int expGain = _duration + (_isPlanned ? 10 : 0);
    currentExp += expGain;

    // レベルアップチェック
    int expNeeded = currentLevel * 100;
    while (currentExp >= expNeeded) {
      currentExp -= expNeeded;
      currentLevel++;
      expNeeded = currentLevel * 100;
    }

    // 保存
    await prefs.setInt('exp', currentExp);
    await prefs.setInt('level', currentLevel);
  }

  Widget _buildDateTimeSelector() {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📅 実施日時', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: Text('日付'),
                    subtitle: Text('${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}'),
                    leading: Icon(Icons.calendar_today, color: Colors.purple),
                    onTap: _selectDate,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    tileColor: Colors.purple[50],
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ListTile(
                    title: Text('時刻'),
                    subtitle: Text('${_selectedTime.format(context)}'),
                    leading: Icon(Icons.access_time, color: Colors.purple),
                    onTap: _selectTime,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    tileColor: Colors.purple[50],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationSelector() {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⏱️ 実施時間', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _duration.toDouble(),
                    min: 5,
                    max: 300,
                    divisions: 59,
                    label: '${_duration}秒',
                    onChanged: (value) => setState(() => _duration = value.round()),
                    activeColor: Colors.purple,
                  ),
                ),
                Container(
                  width: 80,
                  child: Text(
                    '${_duration}秒',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            Text(
              '${(_duration / 60).floor()}分${_duration % 60}秒',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsCard() {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🎯 実施タイプ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SwitchListTile(
              title: Text('📋 計画に沿った実施'),
              subtitle: Text(_isPlanned ? 'ボーナス経験値が付与されます' : '追加実施として記録されます'),
              value: _isPlanned,
              onChanged: (value) => setState(() => _isPlanned = value),
              activeColor: Colors.purple,
            ),
            Divider(),
            Text('📝 メモ（任意）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            TextField(
              controller: _memoController,
              decoration: InputDecoration(
                hintText: '実施した場所や気分など...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.purple),
                ),
              ),
              maxLines: 2,
              onChanged: (value) => _memo = value,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('📝 手動記録追加'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700]),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'アプリ外で実施したプランクを記録に追加できます',
                      style: TextStyle(color: Colors.orange[700]),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            _buildDateTimeSelector(),
            _buildDurationSelector(),
            _buildOptionsCard(),
            SizedBox(height: 24),
            Container(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveRecord,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('保存中...'),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save),
                        SizedBox(width: 8),
                        Text(
                          '💾 記録を保存',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💡 記録のコツ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                  SizedBox(height: 4),
                  Text('• 実際に実施した時間をできるだけ正確に入力', style: TextStyle(fontSize: 12, color: Colors.blue[700])),
                  Text('• 計画通りの実施はボーナス経験値でモチベーションアップ', style: TextStyle(fontSize: 12, color: Colors.blue[700])),
                  Text('• メモ機能で実施環境や感想を記録すると振り返りに便利', style: TextStyle(fontSize: 12, color: Colors.blue[700])),
                ],
              ),
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
  
  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final recordsJson = prefs.getStringList('records') ?? [];
    setState(() {
      _records = recordsJson.map((json) => PlankRecord.fromJson(jsonDecode(json))).toList();
    });
  }

  // 過去7日間のデータを取得
  List<MapEntry<DateTime, List<PlankRecord>>> _getLast7DaysData() {
    final now = DateTime.now();
    final last7Days = List.generate(7, (index) => 
      DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - index)));
    
    return last7Days.map((date) {
      final dayRecords = _records.where((record) => 
        record.date.year == date.year &&
        record.date.month == date.month &&
        record.date.day == date.day
      ).toList();
      return MapEntry(date, dayRecords);
    }).toList();
  }

  // 過去30日間のデータを取得
  List<MapEntry<DateTime, List<PlankRecord>>> _getLast30DaysData() {
    final now = DateTime.now();
    final last30Days = List.generate(30, (index) => 
      DateTime(now.year, now.month, now.day).subtract(Duration(days: 29 - index)));
    
    return last30Days.map((date) {
      final dayRecords = _records.where((record) => 
        record.date.year == date.year &&
        record.date.month == date.month &&
        record.date.day == date.day
      ).toList();
      return MapEntry(date, dayRecords);
    }).toList();
  }

  Widget _buildWeeklyChart() {
    final data = _getLast7DaysData();
    final maxDuration = data.map((entry) => 
      entry.value.isEmpty ? 0 : entry.value.map((r) => r.duration).reduce((a, b) => a > b ? a : b)
    ).reduce((a, b) => a > b ? a : b).toDouble();
    
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📊 過去7日間の実施時間', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Container(
              height: 200,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.map((entry) {
                  final totalDuration = entry.value.fold(0, (sum, record) => sum + record.duration);
                  final maxRecord = entry.value.isEmpty ? 0 : 
                    entry.value.map((r) => r.duration).reduce((a, b) => a > b ? a : b);
                  final barHeight = maxDuration > 0 ? (maxRecord / maxDuration) * 160 : 0.0;
                  
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${totalDuration}s', style: TextStyle(fontSize: 10)),
                      SizedBox(height: 4),
                      Container(
                        width: 30,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: totalDuration > 0 ? Colors.purple : Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${entry.key.month}/${entry.key.day}',
                        style: TextStyle(fontSize: 10),
                      ),
                      Text(
                        ['日', '月', '火', '水', '木', '金', '土'][entry.key.weekday % 7],
                        style: TextStyle(fontSize: 8, color: Colors.grey),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.pushNamed(context, '/manual_add');
          if (result == true) {
            await _loadRecords(); // _loadDataを_loadRecordsに修正
          }
        },
        tooltip: '📝 手動で記録追加',
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add, color: Colors.white), // childを最後に移動
      ),
    );
  }

  Widget _buildStatsCards() {
    final totalRecords = _records.length;
    final totalTime = _records.fold(0, (sum, record) => sum + record.duration);
    final avgTime = totalRecords > 0 ? totalTime / totalRecords : 0;
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
    final weeklyAverages = <double>[];
    
    for (int i = 0; i < 4; i++) {
      final weekData = data.skip(i * 7).take(7);
      final weekTotal = weekData.fold(0, (sum, entry) => 
        sum + entry.value.fold(0, (daySum, record) => daySum + record.duration));
      weeklyAverages.add(weekTotal / 7);
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
                  final maxAvg = weeklyAverages.reduce((a, b) => a > b ? a : b);
                  final height = maxAvg > 0 ? (entry.value / maxAvg) * 120 : 0;
                  
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${entry.value.round()}s', style: TextStyle(fontSize: 10)),
                      SizedBox(height: 4),
                      Container(
                        width: 40,
                        height: height,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text('第${entry.key + 1}週', style: TextStyle(fontSize: 10)),
                    ],
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
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () async {
              final result = await Navigator.pushNamed(context, '/manual_add');
              if (result == true) {
                await _loadRecords(); // _loadDataを_loadRecordsに修正
              }
            },
            tooltip: '📝 手動で記録追加',
          ),
        ],
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
                _buildWeeklyChart(),
                _buildMonthlyTrend(),
                SizedBox(height: 20),
              ],
            ),
          ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.pushNamed(context, '/manual_add');
          if (result == true) {
            await _loadRecords(); // _loadDataを_loadRecordsに修正
          }
        },
        tooltip: '📝 手動で記録追加',
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add, color: Colors.white), // childを最後に移動
      ),
    );
  }
}

class PlankRecord {
  final DateTime date;
  final int duration; // seconds
  final bool isPlanned;
  final String memo;

  PlankRecord({
    required this.date, 
    required this.duration, 
    required this.isPlanned,
    this.memo = '',
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'duration': duration,
    'isPlanned': isPlanned,
    'memo': memo,
  };

  factory PlankRecord.fromJson(Map<String, dynamic> json) => PlankRecord(
    date: DateTime.parse(json['date']),
    duration: json['duration'],
    isPlanned: json['isPlanned'],
    memo: json['memo'] ?? '', // 既存データとの互換性のため
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
  
  // User progress data
  int _level = 1;
  int _exp = 0;
  int _streak = 0;
  List<PlankRecord> _records = [];
  
  // 設定項目
  bool _requireContinuousTime = true; // true: 継続時間重視, false: 総時間重視
  int _minimumRecordTime = 10; // 記録する最低時間（秒）
  bool _dailyPlan = false; // true: 毎日実施, false: 計画通り
  
  // Weekly plan (seconds for each week)
  final List<List<int>> _weeklyPlan = [
    [20, 20, 20], // Week 1: 20sec x 3days
    [30, 30, 30, 30], // Week 2: 30sec x 4days
    [45, 45, 45, 45], // Week 3: 45sec x 4days
    [60, 60, 60, 60, 60], // Week 4: 60sec x 5days
  ];
  
  final List<String> _planNames = [
    '🌱 初心者プラン',
    '💪 基礎プラン', 
    '🔥 中級プラン',
    '⚡ 上級プラン',
    '🎯 カスタムプラン'
  ];
  
  final List<List<List<int>>> _allPlans = [
    // 初心者プラン (より短時間)
    [
      [10, 10, 10], // Week 1: 10sec x 3days
      [15, 15, 15, 15], // Week 2: 15sec x 4days
      [20, 20, 20, 20], // Week 3: 20sec x 4days
      [30, 30, 30, 30, 30], // Week 4: 30sec x 5days
    ],
    // 基礎プラン (元のプラン)
    [
      [20, 20, 20], // Week 1: 20sec x 3days
      [30, 30, 30, 30], // Week 2: 30sec x 4days
      [45, 45, 45, 45], // Week 3: 45sec x 4days
      [60, 60, 60, 60, 60], // Week 4: 60sec x 5days
    ],
    // 中級プラン
    [
      [30, 30, 30], // Week 1: 30sec x 3days
      [45, 45, 45, 45], // Week 2: 45sec x 4days
      [60, 60, 60, 60], // Week 3: 60sec x 4days
      [90, 90, 90, 90, 90], // Week 4: 90sec x 5days
    ],
    // 上級プラン
    [
      [60, 60, 60], // Week 1: 60sec x 3days
      [90, 90, 90, 90], // Week 2: 90sec x 4days
      [120, 120, 120, 120], // Week 3: 120sec x 4days
      [180, 180, 180, 180, 180], // Week 4: 180sec x 5days
    ],
    // カスタムプラン (デフォルト値、後で変更可能)
    [
      [20, 20, 20],
      [30, 30, 30, 30],
      [45, 45, 45, 45],
      [60, 60, 60, 60, 60],
    ],
  ];
  
  // 毎日プランの場合の目標時間（各週の平均時間を毎日実施）
  final List<List<int>> _dailyPlans = [
    [10, 12, 15, 20], // 初心者: 毎日少しずつ
    [20, 25, 30, 40], // 基礎: 毎日中程度
    [30, 40, 50, 70], // 中級: 毎日しっかり
    [60, 80, 100, 140], // 上級: 毎日本格的
    [30, 40, 50, 60], // カスタム: デフォルト値
  ];
  
  int _selectedPlanIndex = 1; // デフォルトは基礎プラン
  int _currentWeek = 0;
  int _currentDay = 0;
  
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

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _level = prefs.getInt('level') ?? 1;
      _exp = prefs.getInt('exp') ?? 0;
      _streak = prefs.getInt('streak') ?? 0;
      _selectedPlanIndex = prefs.getInt('selectedPlanIndex') ?? 1;
      _currentWeek = prefs.getInt('currentWeek') ?? 0;
      _currentDay = prefs.getInt('currentDay') ?? 0;
      
      // 新しい設定項目
      _requireContinuousTime = prefs.getBool('requireContinuousTime') ?? true;
      _minimumRecordTime = prefs.getInt('minimumRecordTime') ?? 10;
      _dailyPlan = prefs.getBool('dailyPlan') ?? false;
      
      final recordsJson = prefs.getStringList('records') ?? [];
      _records = recordsJson.map((json) => PlankRecord.fromJson(jsonDecode(json))).toList();
      
      // カスタムプランのロード
      if (_selectedPlanIndex == 4) { // カスタムプラン
        final customPlanJson = prefs.getStringList('customPlan');
        if (customPlanJson != null) {
          _allPlans[4] = customPlanJson.map((weekJson) => 
            (jsonDecode(weekJson) as List).cast<int>()).toList();
        }
      }
      
      _updateStreak();
    });
  }

  void _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('level', _level);
    await prefs.setInt('exp', _exp);
    await prefs.setInt('streak', _streak);
    await prefs.setInt('selectedPlanIndex', _selectedPlanIndex);
    await prefs.setInt('currentWeek', _currentWeek);
    await prefs.setInt('currentDay', _currentDay);
    
    // 新しい設定項目の保存
    await prefs.setBool('requireContinuousTime', _requireContinuousTime);
    await prefs.setInt('minimumRecordTime', _minimumRecordTime);
    await prefs.setBool('dailyPlan', _dailyPlan);
    
    final recordsJson = _records.map((record) => jsonEncode(record.toJson())).toList();
    await prefs.setStringList('records', recordsJson);
    
    // カスタムプランの保存
    if (_selectedPlanIndex == 4) {
      final customPlanJson = _allPlans[4].map((week) => jsonEncode(week)).toList();
      await prefs.setStringList('customPlan', customPlanJson);
    }
  }

  void _updateStreak() {
    if (_records.isEmpty) {
      _streak = 0;
      return;
    }
    
    final today = DateTime.now();
    final yesterday = today.subtract(Duration(days: 1));
    final todayRecords = _records.where((r) => _isSameDay(r.date, today)).toList();
    
    if (todayRecords.isNotEmpty) {
      // Already completed today, check for consecutive days
      int streak = 1;
      for (int i = 1; i < 30; i++) { // Check last 30 days
        final checkDate = today.subtract(Duration(days: i));
        final hasRecord = _records.any((r) => _isSameDay(r.date, checkDate));
        if (hasRecord) {
          streak++;
        } else {
          break;
        }
      }
      _streak = streak;
    } else {
      // Not completed today, check if completed yesterday
      final yesterdayRecords = _records.where((r) => _isSameDay(r.date, yesterday)).toList();
      if (yesterdayRecords.isEmpty) {
        _streak = 0;
      }
      // If completed yesterday, keep current streak
    }
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
    int finalSeconds = _seconds; // 停止時の秒数を保存
    
    if (_seconds >= _minimumRecordTime) {
      _recordPlank();
    }
    
    setState(() {
      _isRunning = false;
      _isPaused = false;
    });
    
    HapticFeedback.heavyImpact();
    
    // 3秒後にタイマーをリセット
    Timer(Duration(seconds: 3), () {
      if (!_isRunning && !_isPaused) {
        setState(() {
          _seconds = 0;
        });
      }
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _seconds = 0;
    });
    HapticFeedback.heavyImpact();
    
    // 取り消し確認ダイアログ
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('⚠️ 取り消し確認'),
        content: Text('実施中のプランクを取り消しますか？\n記録されません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('続行'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 既に取り消し済み
            },
            child: Text('取り消し'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  void _recordPlank() {
    final today = DateTime.now();
    final isPlanned = _isPlannedSession();
    
    final record = PlankRecord(
      date: today,
      duration: _seconds,
      isPlanned: isPlanned,
    );
    
    setState(() {
      _records.add(record);
      _addExp(_seconds);
      
      // 計画に沿った実施で、かつ目標時間を達成した場合のみ進行
      if (isPlanned) {
        final currentPlan = _getCurrentWeekPlan();
        final targetDuration = currentPlan[_currentDay];
        
        if (_seconds >= targetDuration - 5) { // 許容範囲で達成
          if (_currentDay < currentPlan.length - 1) {
            _currentDay++;
          } else if (_currentWeek < _allPlans[_selectedPlanIndex].length - 1) {
            _currentWeek++;
            _currentDay = 0;
          }
        }
      }
      
      _updateStreak();
    });
    
    _saveData();
    _celebrationController.forward().then((_) => _celebrationController.reset());
    _showCompletionDialog();
  }

  bool _isPlannedSession() {
    if (_currentWeek >= _getCurrentWeekPlan().length) return false;
    final planDuration = _getCurrentWeekPlan()[_currentDay];
    return _seconds >= planDuration - 5 && _seconds <= planDuration + 10;
  }

  List<int> _getCurrentWeekPlan() {
    final currentPlan = _allPlans[_selectedPlanIndex];
    if (_currentWeek >= currentPlan.length) return [60]; // Default to 60 seconds
    return currentPlan[_currentWeek];
  }
  
  // 今日の目標達成度を計算
  double _getTodayProgress() {
    final today = DateTime.now();
    final todayRecords = _records.where((r) => _isSameDay(r.date, today)).toList();
    
    if (todayRecords.isEmpty) return 0.0;
    
    final currentPlan = _getCurrentWeekPlan();
    if (_currentDay >= currentPlan.length) return 1.0;
    
    final targetDuration = currentPlan[_currentDay];
    final maxDuration = todayRecords.map((r) => r.duration).reduce((a, b) => a > b ? a : b);
    
    return (maxDuration / targetDuration).clamp(0.0, 1.0);
  }
  
  // 週全体の達成度を計算
  double _getWeekProgress() {
    final currentPlan = _getCurrentWeekPlan();
    int completedDays = 0;
    
    for (int day = 0; day < currentPlan.length && day <= _currentDay; day++) {
      final targetDate = DateTime.now().subtract(Duration(days: _currentDay - day));
      final dayRecords = _records.where((r) => _isSameDay(r.date, targetDate)).toList();
      
      if (dayRecords.isNotEmpty) {
        final targetDuration = currentPlan[day];
        final maxDuration = dayRecords.map((r) => r.duration).reduce((a, b) => a > b ? a : b);
        if (maxDuration >= targetDuration - 5) { // 許容範囲
          completedDays++;
        }
      }
    }
    
    return completedDays / currentPlan.length;
  }

  void _addExp(int seconds) {
    int expGain = seconds + (_isPlannedSession() ? 10 : 0) + (_streak > 0 ? _streak * 2 : 0);
    _exp += expGain;
    
    // Level up check
    int expNeeded = _level * 100;
    while (_exp >= expNeeded) {
      _exp -= expNeeded;
      _level++;
      expNeeded = _level * 100;
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(Icons.celebration, color: Colors.orange, size: 30),
            SizedBox(width: 10),
            Text('🎉 お疲れ様！ 💪', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('⏰ ${_seconds}秒間のプランクを完了しました！'),
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('🎯 続ける'),
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
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isRunning ? _pulseAnimation.value : 1.0,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: _isRunning 
                  ? [Colors.purple.shade400, Colors.pink.shade400]
                  : [Colors.grey.shade300, Colors.grey.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isRunning ? Colors.purple.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: Text(
                _formatTime(_seconds),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlButtons() {
    return Column(
      children: [
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
                label: '🛑 完了',
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
        SizedBox(height: 16),
        // 設定に応じたヒント表示
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
    final currentPlan = _getCurrentWeekPlan();
    final targetTime = _currentDay < currentPlan.length ? currentPlan[_currentDay] : 60;
    final expNeeded = _level * 100;
    
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
                  Text('🎯 今週の目標', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                  SizedBox(height: 8),
                  Text('${_planNames[_selectedPlanIndex]} - 第${_currentWeek + 1}週', 
                       style: TextStyle(color: Colors.blue[700], fontSize: 12)),
                  Text('⏰ ${targetTime}秒 (📅 ${_currentDay + 1}日目)', 
                       style: TextStyle(color: Colors.blue[700])),
                  SizedBox(height: 8),
                  Text('📊 今日の達成度', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  LinearProgressIndicator(
                    value: _getTodayProgress(),
                    backgroundColor: Colors.blue[100],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green[400]!),
                  ),
                  SizedBox(height: 4),
                  Text('📈 週全体の達成度', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
}

// 計画設定画面
class PlanSettingsScreen extends StatefulWidget {
  @override
  _PlanSettingsScreenState createState() => _PlanSettingsScreenState();
}

class _PlanSettingsScreenState extends State<PlanSettingsScreen> {
  int _selectedPlanIndex = 1;
  bool _requireContinuousTime = true;
  int _minimumRecordTime = 10;
  bool _dailyPlan = false;
  List<List<int>> _customPlan = [
    [20, 20, 20],
    [30, 30, 30, 30],
    [45, 45, 45, 45],
    [60, 60, 60, 60, 60],
  ];
  
  final List<String> _planNames = [
    '🌱 初心者プラン',
    '💪 基礎プラン', 
    '🔥 中級プラン',
    '⚡ 上級プラン',
    '🎯 カスタムプラン'
  ];
  
  final List<String> _planDescriptions = [
    '10秒から始める優しいプラン',
    '20秒から始める標準プラン',
    '30秒から始める挑戦プラン',
    '60秒から始める本格プラン',
    '自分だけのオリジナルプラン'
  ];
  
  final List<List<List<int>>> _allPlans = [
    // 初心者プラン
    [
      [10, 10, 10],
      [15, 15, 15, 15],
      [20, 20, 20, 20],
      [30, 30, 30, 30, 30],
    ],
    // 基礎プラン
    [
      [20, 20, 20],
      [30, 30, 30, 30],
      [45, 45, 45, 45],
      [60, 60, 60, 60, 60],
    ],
    // 中級プラン
    [
      [30, 30, 30],
      [45, 45, 45, 45],
      [60, 60, 60, 60],
      [90, 90, 90, 90, 90],
    ],
    // 上級プラン
    [
      [60, 60, 60],
      [90, 90, 90, 90],
      [120, 120, 120, 120],
      [180, 180, 180, 180, 180],
    ],
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentPlan();
  }

  Future<void> _loadCurrentPlan() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedPlanIndex = prefs.getInt('selectedPlanIndex') ?? 1;
      _requireContinuousTime = prefs.getBool('requireContinuousTime') ?? true;
      _minimumRecordTime = prefs.getInt('minimumRecordTime') ?? 10;
      _dailyPlan = prefs.getBool('dailyPlan') ?? false;
      
      // カスタムプランのロード
      final customPlanJson = prefs.getStringList('customPlan');
      if (customPlanJson != null) {
        _customPlan = customPlanJson.map((weekJson) => 
          (jsonDecode(weekJson) as List).cast<int>()).toList();
      }
    });
  }

  void _savePlan() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selectedPlanIndex', _selectedPlanIndex);
    await prefs.setBool('requireContinuousTime', _requireContinuousTime);
    await prefs.setInt('minimumRecordTime', _minimumRecordTime);
    await prefs.setBool('dailyPlan', _dailyPlan);
    
    if (_selectedPlanIndex == 4) {
      final customPlanJson = _customPlan.map((week) => jsonEncode(week)).toList();
      await prefs.setStringList('customPlan', customPlanJson);
    }
    
    // 計画変更時は進行度をリセット
    await prefs.setInt('currentWeek', 0);
    await prefs.setInt('currentDay', 0);
    
    Navigator.pop(context, true); // 変更があったことを通知
  }

  Widget _buildPlanCard(int index) {
    final isSelected = _selectedPlanIndex == index;
    final plan = index < 4 ? _allPlans[index] : _customPlan;
    
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
                      _planNames[index],
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
                _planDescriptions[index],
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              SizedBox(height: 12),
              ...plan.asMap().entries.map((entry) {
                int weekIndex = entry.key;
                List<int> week = entry.value;
                return Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text('第${weekIndex + 1}週: ', 
                           style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text('${week.join('秒, ')}秒 (${week.length}日)',
                           style: TextStyle(fontSize: 12)),
                    ],
                  ),
                );
              }).toList(),
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

  Widget _buildSettingsCard() {
    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: Text('📅 毎日実施プラン'),
              subtitle: Text('毎日少しずつ vs 計画通りのスケジュール'),
              value: _dailyPlan,
              onChanged: (value) => setState(() => _dailyPlan = value),
              activeColor: Colors.purple,
            ),
            Divider(),
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

  @override
  Widget build(BuildContext context) {
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
                Text(
                  '🎯 プランクプランを選択してください',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                ...List.generate(5, (index) => _buildPlanCard(index)),
                SizedBox(height: 24),
                Text(
                  '⚙️ 実施設定',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                _buildSettingsCard(),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _savePlan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  '💾 プランを保存',
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
  final List<List<int>> initialPlan;
  final Function(List<List<int>>) onSave;

  CustomPlanEditorDialog({required this.initialPlan, required this.onSave});

  @override
  _CustomPlanEditorDialogState createState() => _CustomPlanEditorDialogState();
}

class _CustomPlanEditorDialogState extends State<CustomPlanEditorDialog> {
  late List<List<int>> _plan;

  @override
  void initState() {
    super.initState();
    _plan = widget.initialPlan.map((week) => List<int>.from(week)).toList();
  }

  void _updateDuration(int weekIndex, int dayIndex, int newDuration) {
    setState(() {
      _plan[weekIndex][dayIndex] = newDuration;
    });
  }

  void _addDay(int weekIndex) {
    setState(() {
      _plan[weekIndex].add(30); // デフォルト30秒
    });
  }

  void _removeDay(int weekIndex, int dayIndex) {
    if (_plan[weekIndex].length > 1) {
      setState(() {
        _plan[weekIndex].removeAt(dayIndex);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: EdgeInsets.all(16),
        constraints: BoxConstraints(maxHeight: 600),
        child: Column(
          children: [
            Text(
              '🎯 カスタムプラン編集',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _plan.length,
                itemBuilder: (context, weekIndex) {
                  return Card(
                    margin: EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '第${weekIndex + 1}週',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          ..._plan[weekIndex].asMap().entries.map((entry) {
                            int dayIndex = entry.key;
                            int duration = entry.value;
                            return Row(
                              children: [
                                Text('${dayIndex + 1}日目: '),
                                Expanded(
                                  child: Slider(
                                    value: duration.toDouble(),
                                    min: 10,
                                    max: 300,
                                    divisions: 58,
                                    label: '${duration}秒',
                                    onChanged: (value) =>
                                        _updateDuration(weekIndex, dayIndex, value.round()),
                                  ),
                                ),
                                Text('${duration}秒'),
                                IconButton(
                                  icon: Icon(Icons.remove_circle, color: Colors.red),
                                  onPressed: () => _removeDay(weekIndex, dayIndex),
                                ),
                              ],
                            );
                          }).toList(),
                          TextButton.icon(
                            onPressed: () => _addDay(weekIndex),
                            icon: Icon(Icons.add),
                            label: Text('日を追加'),
                          ),
                        ],
                      ),
                    ),
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
                  onPressed: () {
                    widget.onSave(_plan);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          if (record.memo.isNotEmpty) ...[
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.note, size: 16, color: Colors.grey[600]),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      record.memo,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            icon: Icon(Icons.bar_chart),
            onPressed: () => Navigator.pushNamed(context, '/stats'),
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () async {
              final result = await Navigator.pushNamed(context, '/settings');
              if (result == true) {
                await _loadData(); // 設定変更後にデータを再読込
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