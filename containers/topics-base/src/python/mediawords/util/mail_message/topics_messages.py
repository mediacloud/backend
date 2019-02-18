class TopicSpiderUpdateMessage(TemplateMessage):
    """Generate and return "topic spider update" email message."""

    def __init__(self, to: str, topic_name: str, topic_url: str, topic_spider_status: str):
        if not topic_name:
            raise McMailTemplatesException('"topic_name" is not set.')
        if not topic_url:
            raise McMailTemplatesException('"topic_url" is not set.')
        if not topic_spider_status:
            raise McMailTemplatesException('"topic_spider_status" is not set.')

        topic_name = decode_object_from_bytes_if_needed(topic_name)
        topic_url = decode_object_from_bytes_if_needed(topic_url)
        topic_spider_status = decode_object_from_bytes_if_needed(topic_spider_status)

        TemplateMessage.__init__(
            self=self,
            to=to,
            template_basename='topic_spider_update',
            attributes={
                'topic_name': topic_name,
                'topic_url': topic_url,
                'topic_spider_status': topic_spider_status,
            }
        )
