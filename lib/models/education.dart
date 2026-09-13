class EducationCategory {
  const EducationCategory({
    required this.categoryId,
    required this.title,
    required this.sortOrder,
  });
  final String categoryId;
  final String title;
  final int sortOrder;

  factory EducationCategory.fromMap(Map<String, Object?> map) => EducationCategory(
        categoryId: map['category_id'] as String,
        title: map['title'] as String,
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class EducationContent {
  const EducationContent({
    required this.contentId,
    required this.categoryId,
    required this.title,
    required this.body,
  });
  final String contentId;
  final String categoryId;
  final String title;
  final String body;

  factory EducationContent.fromMap(Map<String, Object?> map) => EducationContent(
        contentId: map['content_id'] as String,
        categoryId: map['category_id'] as String,
        title: map['title'] as String,
        body: map['body'] as String,
      );
}
