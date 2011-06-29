#!/usr/bin/env ruby

require 'sinatra'
require 'wpitjq_generator'
require 'haml'

get '/' do
  haml :index
end

get '/generate' do
  
  halt "no feed" unless params[:feed]
  halt "no site" unless params[:site]

  return Generator.new.for( params[:feed], params[:site] ) 

end
