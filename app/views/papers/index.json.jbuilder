json.array!(@papers) do |paper|
  json.extract! paper, :id, :name, :keywords, :author, :references, :topics
  json.url paper_url(paper, format: :json)
end
