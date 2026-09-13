import 'dart:typed_data';

class EducationMedia {
  const EducationMedia({
    required this.mediaId,
    required this.contentId,
    required this.kind,
    this.caption,
    this.url,
    this.bytes,
    this.mimeType,
    this.createdAtUtc,
  });

  final String mediaId;
  final String contentId;
  final String kind;
  final String? caption;
  final String? url;
  final Uint8List? bytes;
  final String? mimeType;
  final String? createdAtUtc;

  bool get isImage => kind == 'image';
  bool get isLinkMedia => kind == 'media';

  factory EducationMedia.fromMap(Map<String, Object?> map) => EducationMedia(
        mediaId: '${map['media_id']}',
        contentId: '${map['content_id']}',
        kind: '${map['kind']}',
        caption: map['caption']?.toString(),
        url: map['url']?.toString(),
        bytes: map['blob_data'] as Uint8List?,
        mimeType: map['mime_type']?.toString(),
        createdAtUtc: map['created_at_utc']?.toString(),
      );
}
