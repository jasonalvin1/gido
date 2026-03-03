import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/memo_model.dart';
import '../services/app_state.dart';
import '../utils/app_theme.dart';

class AddCategoryScreen extends StatefulWidget {
  const AddCategoryScreen({super.key});

  @override
  State<AddCategoryScreen> createState() => _AddCategoryScreenState();
}

class _AddCategoryScreenState extends State<AddCategoryScreen> {
  String _selectedIcon = 'assets/icons/card.png';
  String _selectedLabel = '카드';
  String _selectedColor = '#2196F3';
  bool _isCustom = false;

  final TextEditingController _customIconController = TextEditingController();
  final TextEditingController _customLabelController = TextEditingController();

  final List<Map<String, String>> defaultIconOptions = [
    {'icon': 'assets/icons/site.png', 'label': '사이트/앱'},
    {'icon': 'assets/icons/bank.png', 'label': '은행/계좌'},
    {'icon': 'assets/icons/birthday.png', 'label': '생일/기념일'},
    {'icon': 'assets/icons/church.png', 'label': '교회/모임'},
    {'icon': 'assets/icons/todo.png', 'label': '할일'},
  ];

  final List<Map<String, String>> iconOptions = [
    {'icon': 'assets/icons/card.png',     'label': '카드'},
    {'icon': 'assets/icons/health.png',   'label': '약/건강'},
    {'icon': 'assets/icons/hospital.png', 'label': '병원'},
    {'icon': 'assets/icons/car.png',      'label': '차량'},
    {'icon': 'assets/icons/travel.png',   'label': '여행'},
    {'icon': 'assets/icons/music.png',    'label': '음악'},
    {'icon': 'assets/icons/book.png',     'label': '책/공부'},
    {'icon': 'assets/icons/money.png',    'label': '돈/금융'},
    {'icon': 'assets/icons/shopping.png', 'label': '쇼핑'},
    {'icon': 'assets/icons/pet.png',      'label': '반려동물'},
    {'icon': 'assets/icons/home.png',     'label': '집/부동산'},
    {'icon': 'assets/icons/work.png',     'label': '직장'},
    {'icon': 'assets/icons/goal.png',     'label': '목표'},
    {'icon': 'assets/icons/repair.png',   'label': '수리'},
    {'icon': 'assets/icons/phone.png',    'label': '휴대폰'},
    {'icon': 'assets/icons/education.png','label': '교육'},
    {'icon': 'assets/icons/food.png',     'label': '음식'},
    {'icon': 'assets/icons/exercise.png', 'label': '운동'},
    {'icon': 'assets/icons/hobby.png',    'label': '취미'},
    {'icon': 'assets/icons/plant.png',    'label': '식물'},
    {'icon': 'assets/icons/misc.png',     'label': '아무거나'},
    {'icon': 'assets/icons/other.png',    'label': '기타'},
  ];

  final List<String> colorOptions = [
    '#2196F3', '#4CAF50', '#E91E63', '#9C27B0',
    '#FF9800', '#00BCD4', '#F44336', '#3F51B5',
    '#795548', '#607D8B',
  ];

  @override
  void dispose() {
    _customIconController.dispose();
    _customLabelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    String icon = _selectedIcon;
    String label = _selectedLabel;

    if (_isCustom) {
      icon = _customIconController.text.trim();
      label = _customLabelController.text.trim();

      if (icon.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이모지를 입력해주세요 😊',
              style: TextStyle(fontSize: 18))),
        );
        return;
      }
      if (label.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('카테고리 이름을 입력해주세요',
              style: TextStyle(fontSize: 18))),
        );
        return;
      }
    }

    final existing = context.read<AppState>().categories;
    final isDuplicate = existing.any((c) => c.name == label);
    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$icon $label 카테고리가 이미 있어요!',
              style: const TextStyle(fontSize: 18)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      return;
    }

    final defaultFields = {
      '사이트/앱': ['사이트명', '아이디', '비밀번호', '웹주소', '메모'],
      '은행/계좌': ['은행명', '계좌번호', '비밀번호', '메모'],
      '생일/기념일': ['이름', '날짜', '관계', '메모'],
      '교회/모임': ['모임명', '요일/시간', '장소', '담당자', '전화번호', '메모'],
      '할일': ['할일', '마감일', '메모'],
    };

    final fields = defaultFields[label] ?? ['메모'];
    final isDefault = defaultFields.containsKey(label);

    final category = Category(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: label,
      icon: icon,
      color: _selectedColor,
      fields: fields,
      isDefault: isDefault,
      sortOrder: 99,
    );

    await context.read<AppState>().addCategory(category);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$icon $label 카테고리를 만들었어요! ✅',
              style: const TextStyle(fontSize: 18)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      Navigator.pop(context);
    }
  }

  Widget _buildIconTile({
    required String icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    bool isDark = false,
    double? height,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : (isDark ? const Color(0xFF555555) : const Color(0xFFE0E0E0)),
            width: isSelected ? 3 : 2,
          ),
          color: isSelected
              ? (isDark ? const Color(0xFF2A2D5E) : const Color(0xFFE8EAF6))
              : (isDark ? AppTheme.darkCard : Colors.white),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CategoryIcon(icon: icon, size: 52),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.white : AppTheme.primaryColor)
                      : (isDark ? AppTheme.darkTextPrimary : const Color(0xFF555555)),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catColor = AppTheme.hexToColor(_selectedColor);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final previewIcon = _isCustom
        ? (_customIconController.text.trim().isEmpty ? '✏️' : _customIconController.text.trim())
        : _selectedIcon;
    final previewLabel = _isCustom
        ? (_customLabelController.text.trim().isEmpty ? '직접입력' : _customLabelController.text.trim())
        : _selectedLabel;

    final existingNames = context.watch<AppState>().categories.map((c) => c.name).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('새 카테고리 만들기'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== 디폴트 카테고리 =====
            Text('기본 카테고리',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkTextPrimary : const Color(0xFF888888))),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                mainAxisExtent: 110,
              ),
              itemCount: defaultIconOptions.length,
              itemBuilder: (context, index) {
                final item = defaultIconOptions[index];
                final icon = item['icon']!;
                final label = item['label']!;
                final isSelected = !_isCustom && _selectedIcon == icon;
                final alreadyExists = existingNames.contains(label);

                return Opacity(
                  opacity: alreadyExists ? 0.7 : 1.0,
                  child: _buildIconTile(
                    icon: icon,
                    label: label,
                    isSelected: isSelected,
                    isDark: isDark,
                    height: 90,
                    onTap: alreadyExists ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$icon $label 카테고리가 이미 있어요!',
                              style: const TextStyle(fontSize: 18)),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                      );
                    } : () => setState(() {
                      _isCustom = false;
                      _selectedIcon = icon;
                      _selectedLabel = label;
                    }),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // ===== 아이콘 선택 =====
            Text('아이콘 선택',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkTextPrimary : const Color(0xFF333333))),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 100,
              ),
              itemCount: iconOptions.length + 1,
              itemBuilder: (context, index) {
                if (index == iconOptions.length) {
                  return GestureDetector(
                    onTap: () => setState(() => _isCustom = true),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _isCustom
                              ? AppTheme.primaryColor
                              : (isDark ? const Color(0xFF555555) : const Color(0xFFE0E0E0)),
                          width: _isCustom ? 3 : 2,
                        ),
                        color: _isCustom
                            ? (isDark ? const Color(0xFF2A2D5E) : const Color(0xFFE8EAF6))
                            : (isDark ? AppTheme.darkCard : Colors.white),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('✏️', style: TextStyle(fontSize: 26)),
                          const SizedBox(height: 4),
                          Text('직접입력',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: _isCustom ? FontWeight.w700 : FontWeight.w500,
                                color: _isCustom
                                    ? (isDark ? Colors.white : AppTheme.primaryColor)
                                    : (isDark ? AppTheme.darkTextPrimary : const Color(0xFF555555)),
                              ),
                              textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  );
                }

                final item = iconOptions[index];
                final icon = item['icon']!;
                final label = item['label']!;
                final isSelected = !_isCustom && _selectedIcon == icon;
                return _buildIconTile(
                  icon: icon,
                  label: label,
                  isSelected: isSelected,
                  isDark: isDark,
                  onTap: () => setState(() {
                    _isCustom = false;
                    _selectedIcon = icon;
                    _selectedLabel = label;
                  }),
                );
              },
            ),

            // ===== 직접입력 모드 =====
            if (_isCustom) ...[
              const SizedBox(height: 24),
              Text('이모지 선택 후 카테고리 이름 직접 입력',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.darkTextPrimary : const Color(0xFF333333))),
              const SizedBox(height: 4),
              Text('이모지 버튼을 누른 후 원하시는 이모지를 선택하세요',
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _customIconController,
                      style: const TextStyle(fontSize: 28),
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      decoration: InputDecoration(
                        hintText: '😊',
                        hintStyle: const TextStyle(fontSize: 28),
                        counterText: '',
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: catColor, width: 2),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _customLabelController,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                      maxLength: 10,
                      decoration: InputDecoration(
                        hintText: '카테고리 이름',
                        counterText: '',
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: catColor, width: 2),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 28),

            // ===== 색상 선택 =====
            Text('색상 선택',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkTextPrimary : const Color(0xFF333333))),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.0,
              ),
              itemCount: colorOptions.length,
              itemBuilder: (context, index) {
                final hex = colorOptions[index];
                final color = AppTheme.hexToColor(hex);
                final isSelected = _selectedColor == hex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = hex),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: color.withAlpha(100), blurRadius: 8, spreadRadius: 2)]
                          : null,
                    ),
                    child: isSelected
                        ? const Center(child: Icon(Icons.check, color: Colors.white, size: 24))
                        : null,
                  ),
                );
              },
            ),
            const SizedBox(height: 40),

            // ===== 만들기 버튼 =====
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: catColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CategoryIcon(icon: previewIcon, size: 28),
                    const SizedBox(width: 8),
                    Text(
                      '$previewLabel 만들기',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}