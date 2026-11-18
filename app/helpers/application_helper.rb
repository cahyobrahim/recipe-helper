module ApplicationHelper
  def markdown(text)
    renderer = Redcarpet::Render::HTML.new(filter_html: true, hard_wrap: true, safe_links_only: true)
    md = Redcarpet::Markdown.new(renderer, autolink: true, fenced_code_blocks: true, tables: true)
    sanitize(md.render(text.to_s))
  end
end
