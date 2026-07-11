/// Mirrors iOS `MessageType` + `MessageTemplate` in `Message.swift`.
enum MessageTemplateKind {
  propertyInquiry,
  scheduleViewing,
  priceDiscussion,
  generalQuestion,
  financingInquiry,
}

class MessageTemplate {
  const MessageTemplate({
    required this.title,
    required this.content,
    required this.kind,
  });

  final String title;
  final String content;
  final MessageTemplateKind kind;

  /// Same copy as iOS `MessageTemplate.templates`.
  static const List<MessageTemplate> templates = [
    MessageTemplate(
      title: 'Property Inquiry',
      content:
          "Hi! I'm interested in learning more about this property. Is it still available?",
      kind: MessageTemplateKind.propertyInquiry,
    ),
    MessageTemplate(
      title: 'Schedule Viewing',
      content:
          "I'd like to schedule a viewing of this property. What times work for you?",
      kind: MessageTemplateKind.scheduleViewing,
    ),
    MessageTemplate(
      title: 'Price Discussion',
      content:
          "I'm interested in this property but would like to discuss the price. Are you open to negotiation?",
      kind: MessageTemplateKind.priceDiscussion,
    ),
    MessageTemplate(
      title: 'Property Details',
      content:
          "Could you provide more details about this property? I'm particularly interested in the condition and any recent updates.",
      kind: MessageTemplateKind.generalQuestion,
    ),
    MessageTemplate(
      title: 'Financing Options',
      content:
          "I'm interested in this property and would like to discuss financing options. Can you help me understand the process?",
      kind: MessageTemplateKind.financingInquiry,
    ),
  ];
}
