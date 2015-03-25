require 'rubygems'
require 'net/http'
require 'nokogiri'
require 'open-uri'
require 'neo4j-core'
require 'pp'
require 'descriptive-statistics'

$visited = []
$follow_calc = []
$follow_info = [] 
$academicstat = {"Professor" => 14,"Associate Professor" => 13,"Assistant Professor" => 12,"Post Doc" => 11,"Doctoral Student" => 10,"PH.D. Student" => 9,"Student (Postgraduate)" => 9,"Senior Lecturer" => 8,"Lecturer" => 7,"Student (Master)" => 6,"Researcher (at an Academic Institution)" => 5,"Student (Bachelor)" => 4,"Researcher (at a non-Academic Institution)" => 3,"Other Professional" => 2}

def create_user(link)
	link = link.chomp('/')
	link = link.sub("http:","https:")
	link = link.sub("www.","api.")
	link = link.sub(".com",".com:443")
	link = link.sub("profiles/","profiles?link=")
	html = open(link, "Authorization" => "Bearer "+$token).read
	profile = JSON.parse(html)[0]
	
	if $visited.include? profile["id"]
		return profile 
	end

	$visited << profile["id"] 

	node = Neo4j::Session.query("MATCH (n:USER) WHERE n.id= \"#{profile["id"]}\" RETURN n").first
	if !(node.nil?)
		return profile 
	end

	
	begin
		research_interests = profile["research_interests"].split(', ')
	rescue
		research_interests = ""
	end
	
	begin
		loc =  profile["location"].values.last
	rescue
		loc =""
	end 
	
	begin
		 discpline = profile["discipline"]["name"]
	rescue
		 discipline = ""
	end
	
	begin 
		subdisciplines = profile["discipline"]["subdisciplines"]
	rescue
		subdisciplines = []
	end

	institutions = []
	begin
		institutions << profile["institution"]
	rescue

	end
	
	begin
		profile["education"].each do |e|
			institutions << e["institution"]
		end
	rescue
	end

	begin 
		profile["employment"].each do |e|
			institutions << e["institution"]
		end
	rescue

	end
	institutions = institutions.compact

	query = Neo4j::Session.query.merge(r: {USER: {id: profile["id"]}}).on_create_set(r: {first_name: profile["first_name"], last_name: profile["last_name"],link: profile["link"], user_type: profile["user_type"],display_name: profile["display_name"], institution: institutions, research_interests: research_interests, academic_status: profile["academic_status"], discipline: discpline, subdisciplines: subdisciplines, created: profile["created"], location: loc,verified: profile["verified"], title: profile["title"], biography: profile["biography"]})
	#pp query
	query.exec
	#usernode = Neo4j::Session.query("MERGE (r:USER {id #{profile["id"]}}) ON CREATE SET r += {first_name: #{profile["first_name"]}, last_name: #{profile["last_name"]}, link: #{profile["link"]}, user_type: #{profile["user_type"]},display_name: #{profile["display_name"]}, institution: #{institutions}, research_interests: #{research_interests}, academic_status: #{profile["academic_status"]}, discipline: #{discipline}, subdisciplines: #{subdisciplines}, created: #{profile["created"]}, location: #{loc},verified: #{profile["verified"]}, title: #{profile["title"]}, biography: #{profile["biography"]}}")
	return profile
end

def crawl_following(user_link)
	followlinks = []
	
	url = user_link + "/following"
	url.sub!("http:","https:")
#	url.sub!("https","http")

	doc = Nokogiri::HTML(open(url))
	
	doc.css(".title a").each do |person| #For each person followed, print the name and URL  
  		followlinks << person[:href]
	end
	
	if doc.at_css(".pagemenu_next") #if the user follows more people, crawl the next page
		followlinks = followlinks +  crawl_following("https://www.mendeley.com"+doc.at_css(".pagemenu_next")[:href])
	end
	
	return followlinks
end

def compute_score(current, follow)
	node = Neo4j::Session.query("MATCH (n:USER) WHERE n.id= \"#{current["id"]}\" RETURN n").first
	current_user = node[:n]
	n = $academicstat[current["academic_status"]]
	current_institution = current["institution"]
	score = Hash.new(0)
	follow.each do |f|
		begin
			if f["user_type"].match("admin")
					score[f["id"]] = 100
			elsif f["user_type"].match("advisor")
					score[f["id"]] = 70
			elsif f["user_type"].match("normal")
					score[f["id"]] = 50
			end
		rescue
			# type attribute not present
		end

		begin 
			if f["discipline"]["name"].match(current["discipline"]["name"])
				score[f["id"]] = score[f["id"]] + 100
			end
		rescue
			# discipline not present
		end

		begin
			if f["discipline"]["subdisciplines"] & current["discipline"]["subdisciplines"]
				score[f["id"]] = score[f["id"]] + 200

			end
		rescue
			#subdisciplines not present
		end

		m = $academicstat[f["academic_status"]] 
		begin
			if m > n
					score[f["id"]] = score[f["id"]] + (m-n + 13)*20
			elsif m == n
					score[f["id"]] = score[f["id"]] + 130
			else
					score[f["id"]] = score[f["id"]] + (m-n + 13)*20
			end
		rescue
		# no academic_status attibute
		end
		begin 
			institutions = [] 
			institutions << f["institution"]

			begin
				f["education"].each do |e|
					institutions << e["institution"]
				end
			rescue
			end

			begin 
				f["employment"].each do |e|
					institutions << e["institution"]
				end
			rescue
			end
			overlap = institutions & current_institution
			score[f["id"]] = score[f["id"]] + overlap*25
		rescue
		end
	end

	current_min = score.values.min
	current_max = score.values.max

	if current_max == current_min
		score.each do |k,n|
			score[k] = 0.5
		end
	else
		min = 0.001
		max = 0.999
		score.each do|k,n|
			score[k] = min + (((n - current_min) * (max - min)) / (current_max - current_min))
		end
	end
	
 
	begin
		score.each do |key,val|
			Neo4j::Session.query.match(user: {USER: {id: current_user["id"]}})
                .match(other: {USER: {id: key}})
                .create_unique("user-[f:following {score: #{val}}]->other ").exec
		end
	rescue
		#
	end

end


def following(followele)
	
	if $follow_calc.include? followele[:user_link]
		return
	end

	$follow_calc << followele[:user_link] 

	follow_profile = []


	following_users = crawl_following(followele[:user_link])
	
		following_users.each do |fuser|
			fprofile = create_user(fuser)
			follow_profile << fprofile
		end
		compute_score(followele[:user_profile],follow_profile) 
		
		if followele[:distance] <= 2
			following_users.zip(follow_profile).each do |fuser, fprofile| 
				followhash = { :user_link => fuser, :user_profile => fprofile, :distance => (followele[:distance]+1) }
				$follow_info.push(followhash)
			end
		end
end

def find_follow
	while $follow_info.any?
		to_follow = $follow_info.shift
		following(to_follow)
	end
end


# first arg user_link 
# second arg auth_token
user_link = ARGV.shift
$token = ARGV.shift

session = Neo4j::Session.open(:server_db, 'http://localhost:7474',basic_auth: { username: 'neo4j', password: 'abhi123'})

user_profile = create_user(user_link)

followhash = { :user_link => user_link, :user_profile => user_profile, :distance => 1 }
$follow_info.push(followhash)
find_follow