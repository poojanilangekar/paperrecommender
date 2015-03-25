require 'rubygems'
require 'net/http'
require 'neo4j-core'
require 'descriptive-statistics'
require 'pp'
require 'open-uri'
require 'nokogiri'
require 'json'





$docs = []
$user_queue =[]
$visited = []
$doc_visited = []

def count_tokens(*args)
  tokens = args.join(" ").downcase.split(/\s/)
  tokens.each do |w|
  	w.gsub!(/\W+/,'')
  end
  tokens.delete_if {|x| x == ""}
  tokens.each do |w|
  	w.gsub!(/[0-9]/,"")
  end
  tokens.delete_if {|x| x == ""}
  tokens.inject(Hash.new(0)) {|counts, token| counts[token] += 1; counts }
end



def compute_relation(central_id,doc)
	if $doc_visited.include?(central_id)
		return
	end

	$doc_visited << central_id

	p = Neo4j::Session.query("MATCH (n: PAPER) WHERE n.id = \"#{central_id}\" RETURN n").first
	document = p[:n]

	doctype = Hash.new(30)

	doctype["patent"] = 100
	doctype["journal"] = 90
	doctype["thesis"] = 80
	doctype["conference_proceedings"] = 70
	doctype["working_paper"] = 60
	doctype["book_section"] = doctype["generic"] = doctype["book"] = 50

	score = Hash.new(0)

	# q = Neo4j::Session.query("MATCH (n:PAPER) WHERE NOT(n.id = \"#{central_id}\") RETURN n").to_a
	readers = [] 
	readers << document[:reader_count]
	doc.each do |ndoc|
		#title
		pp ndoc 
		if ndoc["id"] == document[:id]
			next
		end

		overlap = count_tokens(document[:title],ndoc["title"])
		match=0
		overlap.each_value do |v|
			if v == 2
				match = match + 1
			end  
		end
		score[ndoc["id"]] = (match*100/overlap.length)  
		#keywords
		begin 
			dockey = document[:keywords].map(&:downcase)
		rescue
			dockey = []
		end
		begin
			nkey = ndoc["keywords"].map!(&:downcase)
		rescue
			nkey = []
		end
		begin
			score[ndoc["id"]] += ((dockey & nkey).length*100)/dockey.length
		rescue
			#0 increment 
		end
		#authors
		begin 
			docauth = document[:authors]
		rescue
			docauth = []
		end
		begin 
			nauth = ndoc["authors"]
		rescue
			nauth = []
		end

		begin
		score[ndoc["id"]] += (docauth&nauth).length * 10
		rescue
		end

		score[ndoc["id"]] += doctype[ndoc["type"]]

		
		begin 
			score[ndoc["id"]] += 10000/((Time.now.year - ndoc["accessed"][0])*365 + (Time.now.month - ndoc["accessed"][1])*30 + (Time.now.day - ndoc["accessed"][2]))
		rescue
			#
		end
		
		begin 
			score[ndoc[:id]] += 10000/((Time.now.year - ndoc["year"])*365 + (Time.now.month - ndoc["month"])*30 + (Time.now.day - ndoc["day"]))
		rescue
			#
		end
		readers << ndoc["reader_count"]

		begin 
			ndoc["reader_count_by_country"].each do |k,c|
				begin
					score[ndoc["id"]] += c * 10 
				rescue
				end
			end
		rescue
		end
		begin 
			ndoc["reader_count_by_subdiscipline"].each do |k,s|
				begin
					score[ndoc["id"]] += s * 10 
				rescue
				end
			end
		rescue
		end
		begin
			ndoc["reader_count_by_academic_status"].each do |k,as|
				begin
					score[ndoc["id"]] += as * 10 
				rescue
				end
			end
		rescue
		end
	end
	readerstats = DescriptiveStatistics::Stats.new(readers)
	doc.each do |ndoc|
		begin
		score[ndoc["id"]] += readerstats.percentile_from_value(ndoc["reader_count"])
		rescue
		#
		end

	end

	puts score 

	current_min = score.values.min
	current_max = score.values.max

	min = 0.001
	max = 0.999
	score.each do|k,n|
		score[k] = min + (n - current_min) * (max - min) / (current_max - current_min)
	end
	score.each do |key,val|
			Neo4j::Session.query.match(central: {PAPER: {id: document["id"]}})
                .match(other: {PAPER: {id: key}})
                .create_unique("central-[f:related_to {score: #{val}}]->other ").exec
		# rel = doc.create_rel(:related_to, x, score: score[ndoc[:id]])
	end

	scorestats = DescriptiveStatistics::Stats.new(score.values)
	threshold = scorestats.mean
		doc.each do |ndoc|
			if ndoc["id"] == document[:id]
				next
			end
			if score[ndoc["id"]] >= threshold
				compute_relation(ndoc["id"],doc)
			end
		end

end


def create_docs (papers)
	papers.each do |d|
		authors = [] 
		begin
			d["authors"].each do |a|
				authors << a["first_name"] + " " + a["last_name"]
			end
		rescue 
			authors = []
		end
		docnode = Neo4j::Node.create({id: d["id"], title: d["title"], type: d["type"], authors: authors, year: d["year"], month: d["month"], day: d["day"], source: d["source"], keywords: d["keywords"], accessed: d["accessed"], reader_count: d["reader_count"], abstract: d["abstract"]}, :PAPER)
		begin
			reader_count_by_academic_status = []
			d["reader_count_by_academic_status"].each do |key, value|
				docnode[key.to_sym] = value
				reader_count_by_academic_status << key
			end
			docnode[:reader_count_by_academic_status] = reader_count_by_academic_status
		rescue
			#academic status details not found
		end

		begin 
			reader_count_by_country =[]
			d["reader_count_by_country"].each do |key, value|
				docnode[key.to_sym] = value
				reader_count_by_country << key
			end
			docnode[:reader_count_by_country] = reader_count_by_country
		rescue
		#country details not found  
		end
		begin
			reader_count_by_subdiscipline = []
			d["reader_count_by_subdiscipline"].each do |key,value|
				docnode[key.to_sym] = value.values.inject(:+)
				reader_count_by_subdiscipline << key
			end
			docnode[:reader_count_by_subdiscipline] = reader_count_by_subdiscipline
		rescue
			#subdiscipline details not found 
		end
	end
end





def match(udocs,user)
	papers = []
	udocs.each do |d|
		cnt = 0
		$key.each do |k|
			if d["abstract"].include?(k)
				cnt = cnt + 1
			end
		end
		if cnt == ($key.length/2)
		 	papers << d
		end
	end
	create_docs(papers)
	puts "-----------------------hi------------------------------------------"
	most_recent = 0
	scores = Hash.new(0)
	
	papers.each do |d|
		if d["year"] > most_recent then
			most_recent = d["year"]
		end
	end
	papers.each do |d|
		scores[d["id"]] = 0.99/ (1 + (most_recent - d["year"]))
	end
	pp scores
	current_min = scores.values.min 
	current_max = scores.values.max 
	min  = 0.001
	max  = 0.999
	scores.each  do |key,val|
		scores[key] = min + (val - current_min)*(max - min)/(current_max - current_min)
		puts key 
		puts val 
		puts "---------------"
		Neo4j::Session.query.match(user: {USER: {id: user["id"]}})
               .match(p: {PAPER: {id: key}})
               .create_unique("user-[f:author_of {score: #{val}}]->p ").exec


	end
	$docs = $docs + papers
end



def user_papers()
	if $user_queue.empty?
		return 
	end
	curr = $user_queue.shift
	if $visited.include?(curr) then
		#	puts "Already visited"
	else
		$visited << curr
  	 	name = curr[:first_name] +' '+ curr[:last_name]
    	name.gsub!(" ","%20")
   		begin
			url = "https://api.mendeley.com:443/search/catalog?author="+name+"&view=all"
			html = open(url, "Authorization" => "Bearer #{$token}").read
			udocs = JSON.parse(html)
			match(udocs,curr)
		rescue
			#something here
		end
		people = Neo4j::Session.query("MATCH (n:USER)-[:following]->(a:USER) WHERE n.id =\"#{curr[:id]}\" RETURN a").to_a
		people.each do |peop|
			p = peop[:a]
			$user_queue << p
		end
	end
	user_papers
end



session = Neo4j::Session.open(:server_db, 'http://localhost:7474',basic_auth: { username: 'neo4j', password: 'abhi123'})
id = ARGV.shift
$token = ARGV.shift
$key = ARGV
keywords = ""
$key.each do |k|
	keywords << k << "+"
end
keywords.gsub!(" ","%20")
keywords = keywords.chomp('+')
url = "https://api.mendeley.com:443/search/catalog?query="+keywords+"&view=all&limit=100"
#html = open(url, "Authorization" => "Bearer MSwxNDI1MDQwOTk3OTE1LDIxODE3MTEzMSw3MTIsYWxsLCxocmM3b0RFMlgtbjJZTF9UUGo5LXNTS0VJMEk").read
html = open(url,"Authorization" => "Bearer #{$token}").read
$docs = JSON.parse(html)
create_docs($docs)
fid = $docs[0]["id"]
dn = Neo4j::Node.create({fid: fid, keywords: $key}, :FIRSTPAPER) 
user = Neo4j::Session.query("MATCH (n:USER) WHERE n.id=\"#{id}\" RETURN n").first
$user_queue << user[:n]
user_papers()

compute_relation($docs[0]["id"], $docs)