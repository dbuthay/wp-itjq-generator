#!/usr/bin/env ruby

require 'sinatra'
require 'wpitjq_generator'
require 'haml'

default_themes_dir = File.dirname(__FILE__) + "/public/defaults"

get '/' do
  haml :index
end

get '/generate' do
  
  halt "no feed" unless params[:feed]
  halt "no site" unless params[:site]

  # check for precalculated themes .. easy way out!
  theme = params[:theme] || ""
  theme = theme.downcase.gsub(" ", "_") + ".js"

  if theme && File.exists?("#{default_themes_dir}/#{theme}") then
    return File.new "#{default_themes_dir}/#{theme}"
  end

  # else, calculate the js for this theme
  return Generator.new.for( params[:feed], params[:site] ) 

end
