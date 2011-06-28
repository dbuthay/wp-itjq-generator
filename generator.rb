#!/usr/bin/env ruby

require 'nokogiri'

class DummyNode
  def text
    ""
  end
end

def common_prefix( arr )
  prefix = arr.first.dup
  arr[1..-1].each do |e|
    prefix.slice!(e.size..-1) if e.size < prefix.size   # optimisation
    prefix.chop! while e.index(prefix) != 0
  end

  return prefix.slice!(0, prefix.rindex('/'))
end


def common_parent(nodes)
  ancestors = nodes.map { |n|  n.ancestors }
  return ancestors.reduce(:&).first
end


def traverse(n1, n2, n1Specials, indent = 0)
  return unless n1 && n2

  if n1.name == n2.name then
    
    tabs = "\t" * (indent + 1)
    buff = "#{tabs}#{jQueryFyNodes(n1, n2, n1Specials)}\n"

    if n1.children.length() == n2.children.length() then
      n1.children.to_a.each_index do |idx|
        buff += traverse(n1.children[idx], n2.children[idx], n1Specials, indent + 1)
      end

    end

  end

  buff += ")\n"

  return buff
end


def jQueryFyNodes( n1, n2, specials )
  return "" unless n1.name == n2.name

  if n1.text? and n2.text? then
    if n1.text() == n2.text() then
      if n1.text().strip().empty? then 
        return ""
      else
        return ".text('#{n1.text}'"
      end

    else 
      case n1
        when specials["title"] 
          return ".text ( item.post_title "
        when specials["description"] 
          return ".html( item.snippet_post_content || item.post_content.substr(0, 200)"
      end
    end
  end

  buff = ".append( jQuery( '<#{n1.name}/>' )"

  dummy = DummyNode.new
  # handle classes
  cls = ( n1.attribute("class") || dummy ).text.split() & ( n2.attribute("class") || dummy ).text.split()
  cls.each do |cl|
    buff += ".addClass('#{cl}')"
  end

  # handle some specials nodes .. As and IMGs
  case n1.name
    when 'a'
      # keep href ?
      if n1.attribute('href') != n2.attribute('href') then
        buff += ".attr('href', item.url )"
      else
        buff += ".attr('href','#{n1.attribute('href')}' )"
      end
    when 'img'
      # keep src ?
      if n1.attribute('src') != n2.attribute('src') then
        buff += ".attr('src', item.thumbnail )"
      else
        buff += ".attr('src','#{n1.attribute('src')}' )"
      end
  end

  buff
end


def jQueryFy( node, specials, indent = 0)

  buff = "jQuery( '<#{node.name()}/>')"

  # TODO parse css styling here
  node.search("./@class").each do |cl|
    buff += ".addClass('#{cl.text()}')" 
  end


  buff += "\n"

  tabs = "\t" * (indent + 1)

  case node
    when specials["title"]
      # title node, may be a link
      buff+= "#{tabs}.text( ' + item.post_title +' )\n"
    when specials["description"]
      # text node .. snippet here
      buff+= "#{tabs}.html( ' + item.snippet_post_content || item.post_content.substr(0, 200) +' )\n"
    else
      # regular, non interesting node
      node.children().each do |c|
        next unless c.elem?
        buff += "#{tabs}.append( "
        buff += jQueryFy(c, specials, indent +1)
        buff += "#{tabs})\n"
      end
  end

  return buff
end


dir = ARGV[0] || "."
rss = Nokogiri::XML(open("#{dir}/rss.xml"))
blog = Nokogiri::HTML(open("#{dir}/blog.html"))


items = rss.xpath("//item")
titles = rss.xpath("//item/title")
dates = rss.xpath("//item/pubDate")


paired_items = {}


# for each item, try to find a blog node matching its
# - title
# - description
#
# that way, we can tell which elements contains them all, and assume 
# that's a blog-item.
items.each do |n|
  paired_items[n] = {}
  ["title", "description"].each do |type|
    node = n.xpath(type).first
    nodes = []
    blog.css("body").first.traverse do |b|
      if b.text()[0,50] == node.text()[0,50] then
        nodes << b
      end
    end
    paired_items[n][type] = nodes
  end

end




# So, for each item we have a mapping from
# content type => blog node that matches
paired_items.each_pair do |i, m|

  m.each_pair do |type, nodes|
    # try to find out the best node for each one
    if nodes.length == 0 then
      paired_items.delete(i)
      next
    end

    if nodes.length == 1 then
      print "no use on finding the best node for #{i.path} .. there's only one\n"

    end

     
    if nodes.length > 1 then
      print "finding the best #{type} node for #{i.path}\n"

      # get rid of text nodes
      #nodes.reject! {|n| n.text? }
      nodes.sort_by! {|n| n.ancestors.size }
      nodes.each do |n| 
        print "\t", n.path, "\n"
      end
    
    end
    
    
    # keep the best one .. no need for the others 
    paired_items[i][type] = nodes.last

  end
end




# ok, so I got for every item a path for its title and description
# try to find out if there are outliers, and discard them 
lengths = {}
paired_items.values.each do |m|
  m.each_pair do |type, node|
    l = node.ancestors.size

    # initialize if needed
    lengths[type] = {} unless lengths[type]
    lengths[type][l] = 0 unless lengths[type][l]

    # and count
    lengths[type][l] += 1 
  end
end

lengths.each_pair do |type, counts|
  counts = counts.sort {|a,b| a[1] <=> b[1] }
  
  paired_items.each_pair do |item, m|
    # only keep those whose length equals the most likely one 
    paired_items.delete(item) unless m[type].ancestors.size  == counts.last.first
  end

end


# find the DOM element representing each item .. should be the common parent for title / description for each item.
parent_tracking = {} 
paired_items.each_pair do |i, m|

  prefix = common_parent(m.values)
  print "the container for #{i.path} is #{prefix.path} .. #{prefix.attribute('class')}\n"

  parent_tracking[i] = prefix

end

print traverse(parent_tracking.values[-1], parent_tracking.values[-2], paired_items[parent_tracking.keys[-1]])


#container = common_parent( parent_tracking.values)

#print "the CONTAINER is #{container.path} .. #{container.attribute('class')}\n"


#print jQueryFy( blog.xpath(parent_tracking.first.last() ).first(), paired_items.first.last)

exit



