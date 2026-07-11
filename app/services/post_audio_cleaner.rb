class PostAudioCleaner
  def self.clean(markdown_body)
    new.clean(markdown_body)
  end

  def clean(markdown_body)
    text = markdown_body.to_s.dup

    # Remove code blocks (fenced)
    text.gsub!(/```.*?```/m, "")
    # Remove inline code
    text.gsub!(/`[^`]+`/, "")
    # Remove Markdown images
    text.gsub!(/!\[([^\]]*)\]\([^)]+\)/, "")
    # Remove links but keep link text
    text.gsub!(/\[([^\]]+)\]\([^)]+\)/, '\1')
    # Remove horizontal rules
    text.gsub!(/^---+$/, "")
    # Remove HTML tags
    text.gsub!(/<[^>]*>/, "")
    # Remove blockquotes markers
    text.gsub!(/^>\s?/, "")
    # Remove list markers
    text.gsub!(/^[\s]*[-*+]\s+/, "")
    text.gsub!(/^[\s]*\d+\.\s+/, "")
    # Remove table separators
    text.gsub!(/^[\s]*\|[-:| ]+\|[\s]*$/, "")
    text.gsub!(/^\|/, "")
    text.gsub!(/\|$/, "")
    # Remove heading markers but keep text
    text.gsub!(/^[#]{1,6}\s+/, "")
    # Remove control characters except newlines
    text.gsub!(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
    # Replace Unicode symbols with period to break up long sentence runs
    text.gsub!(/\p{So}|\p{Sm}|\p{Sk}/, ".")
    # Collapse whitespace (preserve paragraph breaks)
    text.gsub!(/\n{3,}/, "\n\n")
    text.gsub!(/[ \t]+/, " ")
    text.strip!
    text.presence || ""
  end
end
