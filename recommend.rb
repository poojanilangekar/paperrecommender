require 'open-uri'
require 'neo4j-core'
require 'pp'
require 'andand'
require 'descriptive-statistics'
require 'algorithms'

include Containers 
$visited = [] 
$docs = []
$persons = []
$q = PriorityQueue.new
$h = MaxHeap.new
$main_id = ""

$l1 = 0.85
$l2 = 0.65
$a1 = 0.35
$a2 = 0.45

def recompute(t)
	if t == "PAPER"
		$l1 = $l1*0.5
		$l2 = $l2/0.5
		$a2 = $a2*0.3
		$a1 = $a1/0.3
	else
		$l1 = $l1/0.5
		$l2 = $l2*0.5
		$a1 = $a1*0.3
		$a2 = $a2/0.3
	end
end

def find_next
	trav = $q.pop
	tscore = $h.pop
	if $visited.include? trav[1]
		find_next
		return
	end
	node = Neo4j::Session.query("MATCH (n) WHERE n.id = \"#{trav[1]}\" RETURN n, labels(n) AS t").first
	if node[:t].first == "USER" and ($persons.length != 20)
		$persons << node[:n]
		recompute("USER")
	elsif node[:t].first == "PAPER" and $docs.length != 50
		$docs << node[:n]
		recompute("PAPER") 
	else
		find_next
		return 
	end

	if ($persons.length == 20) and ($docs.length == 50)
		return
	end
	traverse(trav[1],tscore)
end

def traverse(id, tscore)
	$visited << id
	node = Neo4j::Session.query("MATCH (n) WHERE n.id = \"#{id}\" RETURN n, labels(n) AS t").first
	rel = Neo4j::Session.query("MATCH (n)-[r]->(p) WHERE n.id = \"#{id}\" RETURN r,p, labels(p) AS t").to_a
	rel.each do |re|
		if node[:t].first == "USER"
			if re[:t].first == "USER"
				$q.push([id,re[:p][:id]],(tscore+re[:r][:score])*$a1)
				$h.push((tscore+re[:r][:score])*$a1)
			else
				crel = Neo4j::Session.query("MATCH (a:PAPER)-[r]->(b:PAPER) WHERE a.id = \"#{$main_id}\" AND b.id = \"#{re[:p][:id]}\" RETURN r").first
				if crel	
					$q.push([id,re[:p][:id]],(tscore+re[:r][:score])*$l1)
					$h.push((tscore+re[:r][:score])*$l1)
				end
			end
		else
			crel = Neo4j::Session.query("MATCH (a:PAPER)-[r]->(b:PAPER) WHERE a.id = \"#{$main_id}\" AND b.id = \"#{re[:p][:id]}\" RETURN r").first
			if crel	
				$q.push([id,re[:p][:id]],(tscore+re[:r][:score])*$a2)
				$h.push((tscore+re[:r][:score])*$a2)
			end 
		end

	end

	if node[:t].first == "PAPER"
		rel = Neo4j::Session.query("MATCH (n)-[r]->(p) WHERE p.id = \"#{id}\" RETURN r,n, labels(n) AS z").to_a
		rel.each do |re|
			if re[:z].first == "USER"
				$q.push([id,re[:n][:id]],(tscore+re[:r][:score])*$l2)
				$h.push((tscore+re[:r][:score])*$l2)
			end
		end
	end
	find_next
end

def rank_docs
	selected_title = []
	$docs.each do |d|	
		doc_keys = []
		if d[:keywords]
			d[:keywords].each do |k|
				doc_keys << k.downcase
			end
		end
		if (d[:keywords] & $keywords) == nil
			$docs.delete(d)
		end
	end
	$docs = $docs.sort{ |a,b| [a[:year].to_i,a[:reader_count].to_i] <=> [b[:year].to_i, b[:reader_count].to_i]}
	$docs = $docs.reverse!
	unique_title = []
	selected_title =[]
	$docs.each do |d|
		if !(selected_title.include? d[:title].downcase)
			selected_title << d[:title].downcase
			unique_title << d
		end

	end
	$docs.clear
	$docs = unique_title
end



session = Neo4j::Session.open(:server_db, 'http://localhost:7474',basic_auth: { username: 'neo4j', password: 'abhi123'})
id = ARGV.shift
$keywords = []
ARGV.each do |k|
	$keywords << k.downcase
end 
input_user = Neo4j::Session.query("MATCH (u:USER) WHERE u.id = \"#{id}\" RETURN u").first
inptuser = input_user[:u]

max = 0
pap = Neo4j::Session.query("MATCH (x:FIRSTPAPER) RETURN x").to_a
pap.each do |p|
	overlap = (p[:x]["keywords"] & $keywords).length
	if overlap > max
		$main_id = p[:x]["fid"]
	end
	max = overlap
end

c = Neo4j::Session.query("MATCH (a:PAPER) WHERE a.id = \"#{$main_id}\" RETURN a").first
to = c[:a]
#a = inptuser.create_rel(:author_of,to, {score: 0.999})

Neo4j::Session.query.match(user: {USER: {id: inptuser["id"]}})
                .match(other: {PAPER: {id: $main_id}})
                .create_unique("user-[f:author_of {score: 0.999}]->other ").exec
puts "----------------------finish-------------------"
traverse(id,0)
# $keywords = []
# ARGV.each do |k|
# 	$keywords << k.downcase
# end 

# $persons.each do |p|
# 	puts p.labels
# 	pp p[:display_name]
# end
 rank_docs
# $docs.each do |d|
# 	puts d.labels
# 	pp d[:title]
# 	pp d[:id]
# 	pp d[:authors]
# end
# puts $docs.count

# puts "<html>"
# puts "<body align=\"center\">"
# puts "<h1>"

# puts "PEOPLE"
# puts "</h1>"
# $persons[0..15].each do |per|
# 	puts "<p>"+per[:display_name]+"</p>"
# end
# rank_docs
# puts "<h1>PAPER</h1>"
# puts "<table>"
# $docs[0..15].each do |d| 
# 	puts "<tr>"
# puts "<td>"	+  d[:title].to_s + "</td>"
# puts "<td>"	+ d[:reader_count].to_s + "</td>"
# 	puts "<td>" + d[:year].to_s + "</td>"
# 	puts "<tr>"
# end  
# puts "</body> </html>"

return $persons[0..15],$docs[0..15]
y = Neo4j::Session.query("MATCH (a:USER)-[r]->(b:PAPER) WHERE a.id = \"#{id}\" AND b.id = \"#{$main_id}\" DELETE r")
# del = Neo4j::Session.query("MATCH a-[r]->b DELETE a,r")
# del = Neo4j::Session.query("MATCH a DELETE a")

