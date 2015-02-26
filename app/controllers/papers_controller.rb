
  require 'open-uri'
  require 'rest-client'
  require 'nokogiri'
  require 'rubygems'
require 'net/http'
require 'neo4j-core'
require 'descriptive-statistics'
require 'pp'
require 'json'

  class PapersController < ApplicationController
    before_action :set_paper, only: [:show, :edit, :update, :destroy]

    # GET /papers
    # GET /papers.json
    def index
      @papers = Paper.all
    end

    # GET /papers/1
    # GET /papers/1.json
    def show
    end

    # GET /papers/new
    def new
      @paper = Paper.new
    end

    # GET /papers/1/edit
    def edit
    end

    # POST /papers
    # POST /papers.json
    def create
      @paper = Paper.new(paper_params)
      respond_to do |format|
        if @paper.save
        filename =  @paper.userdoc.path      
        response = RestClient.post('http://maui-indexer.appspot.com/mauiapp',
          :document => File.new(filename,"rb"),
          :domain => "keywords")
        doc = Nokogiri::HTML(response)
        keywords = ""
        doc.css("#keywords a").each do |k|
          keywords << k << ' '
        end
        puts keywords 
        textfile = `pdftotext #{filename} -`
        ref =[]
        #textfile.reverse_each do|s|
        #if s.upcase == "REFERENCES\n"
      #break
     #end
     #ref << s
  #end
  #ref.reverse_each do |s|
  #  puts s
  #end
        url = "http://wikipedia-miner.cms.waikato.ac.nz/services/wikify?source=" + URI::encode(keywords.force_encoding('ASCII-8BIT')) + "&minProbability=0.1"
        doc = Nokogiri::XML(open(url))
        topics  = []
        doc.css("detectedTopic").each do |t|
          puts t
          topics << t[:title]<<t[:weight] 
        end
        puts topics
        @paper.keywords = keywords
        @paper.topics = topics

keywords.gsub!(" ","%20")
keywords = keywords.chomp('+')
url = "https://api.mendeley.com:443/search/catalog?query="+keywords+"&view=all&limit=100"
html = open(url, "Authorization" => "Bearer #{session[:mendeley_token]}").read
docs = JSON.parse(html)
session = Neo4j::Session.open(:server_db, 'http://localhost:7474')

docs.each do |d|
  puts "ID: " + d["id"]
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


       # puts `ruby ~/rails_project/maui_rest.rb "#{@paper.userdoc.path}"`
          @paper.save 
          format.html { redirect_to @paper, notice: 'Paper was successfully created.' }
          format.json { render :show, status: :created, location: @paper }
        else
          format.html { render :new }
          format.json { render json: @paper.errors, status: :unprocessable_entity }
        end
    end
  end

    # PATCH/PUT /papers/1
    # PATCH/PUT /papers/1.json
    def update
      respond_to do |format|
        if @paper.update(paper_params)
          format.html { redirect_to @paper, notice: 'Paper was successfully updated.' }
          format.json { render :show, status: :ok, location: @paper }
        else
          format.html { render :edit }
          format.json { render json: @paper.errors, status: :unprocessable_entity }
        end
      end
    end

    # DELETE /papers/1
    # DELETE /papers/1.json
    def destroy
      @paper.destroy
      respond_to do |format|
        format.html { redirect_to papers_url, notice: 'Paper was successfully destroyed.' }
        format.json { head :no_content }
      end
    end

    private
      # Use callbacks to share common setup or constraints between actions.
      def set_paper
        @paper = Paper.find(params[:id])
      end

      # Never trust parameters from the scary internet, only allow the white list through.
      def paper_params
        params.require(:paper).permit(:name, :keywords, :author, :references, :topics,:userdoc)
      end
  end
