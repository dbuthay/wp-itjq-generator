#!/usr/bin/env ruby

require 'nokogiri'
require 'date'
require 'open-uri'

class DummyNode
  def text
    ""
  end
end


class Generator 

  def initialize
  end

  def common_parent(nodes)
    ancestors = nodes.map { |n|  n.ancestors }
    return ancestors.reduce(:&).first
  end


  def is_author_node(node)
    clazzez = ['author', 'vcard']
    node.ancestors.each do |p|
      attr = p.attribute("class") || DummyNode.new
      clazzez.each do |clazz|
        if attr.text.index(clazz) != nil then
          print "#{node}"
          return true
        end
      end
    end 

    return false
  end


  def traverse(n1, n2, specials, indent = 0)
    return "" unless n1 && n2
    if n1.comment? && n2.comment? then
      return ""
    end


    if n1.name == n2.name then

      # handle text nodes .. 
      if n1.text? and n2.text? then
        if n1.text() == n2.text() then
          if n1.text().strip().empty? then 
            return ""
          else
            return ".text('#{n1.text}')"
          end

        else 
          case n1
            when specials["title"] 
              return ".text( item.post_title )"
            when specials["description"] 
              return ".html( item.snippet_post_content || item.post_content.substr(0, 200) ).append('...').prepend('...')"
            else
              if is_author_node(n1) then
                return ".text( item.post_author )"
              else
                # last resource
                begin
                  DateTime.parse(n1.text)
                  return ".text( d.toLocaleDateString() )"
                rescue 
                  # ignore
                end
              end
          end
        end
      end



      # handle regular nodes
      tabs = "\t" * (indent + 1)
      if indent == 0 then
        append = ""
      else 
        append = ".append("
      end

      buff = "\n#{tabs}#{append}jQuery( '<#{n1.name}/>' )"

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


      # and traverse children

      # same count? it may be just formatting markup, or meta
      # or sharing .. not super post-depending
      if n1.children.length() == n2.children.length() then
        n1.children.to_a.each_index do |idx|
          buff += traverse(n1.children[idx], n2.children[idx], specials, indent + 1 ) || ""
        end
      else
        # So this changes from post to post .. it MAY be the content .. 
        if ( specials["description"].ancestors[0..2].index(n1) || 0 ) >= 0 then
          buff += ".html( item.snippet_post_content || item.post_content.substr(0, 200) )"
        end
      end

      buff += "\n#{tabs}"
      if indent > 0 then
        buff += ")"
      end
    end


    buff
  end




  def for(feed, site)


    rss = Nokogiri::XML(open(feed))
    blog = Nokogiri::HTML(open(site))


    items = rss.xpath("//item")
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
          if b.text()[0,20].downcase.strip == node.text()[0,20].downcase.strip then
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
          break
        end

        if nodes.length == 1 then
          #print "no use on finding the best node for #{i.path} .. there's only one\n"

        end

         
        if nodes.length > 1 then
          #print "finding the best #{type} node for #{i.path}\n"

          nodes = nodes.sort_by {|n| n.ancestors.size }
        
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
      #print "the container for #{i.path} is #{prefix.path} .. #{prefix.attribute('class')}\n"

      parent_tracking[i] = prefix

    end

  
    # so we got almost everything 
    fmt = traverse(parent_tracking.values[-1], parent_tracking.values[-2], paired_items[parent_tracking.keys[-1]])


    container = common_parent( parent_tracking.values )
    input = blog.css("input[name='s']").first
    form = input.ancestors.css("form").first


    if input.attribute("id") then
      input = "##{input.attribute('id')}"
    else 
      input = "input[name='s']"
    end

    if container.attribute("id") then
      container = "##{container.attribute("id")}"
    elsif container.attribute("class") then
      container_class = "#{container.name}.#{container.attribute('class')}"
      possible_containers = blog.css(container_class)
      if possible_containers.size() == 1 then
        container = container_class
      end
    end


    buff =  "
    // THIS CODE WAS AUTO GENERATED BY WP-ITJQ-GENERATOR
    // http://wp-it-jq.cloudfoundry.com on #{Time.now}
    // YOU SHOULD VERIFY THAT THE FOLLOWING ITEMS ARE OK:
    //  - dates
    //  - urls (comment urls ?)
    //  - author names
    //  - image urls

    jQuery(window).load( function() {
      var fmt = function(item) {
        var d = new Date( item.timestamp * 1000);
        var r = #{fmt};
        return r;
      };

      var setupContainer = function($el) {
        $el.children().not('#stats, #paginator').detach(); 
      }

      var afterRender = function($el) {
        var p = jQuery('#paginator').detach();
        // send it to the bottom of the results
        $el.append(p);
      }

      // create some placeholders
      var stContainer = jQuery('<div/>').attr('id','stats').hide();
      stContainer.append(jQuery('<span/>')); // deal with stats wanting something inside the container, to 'replace'
      stContainer.indextank_StatsRenderer();

      var pContainer = jQuery('<div/>').attr('id','paginator').hide();
      pContainer.indextank_Pagination({maxPages:5});

      jQuery('#{container}').prepend(stContainer).append(pContainer);

      

      
      var rw = function(q) { return 'post_content:(' + q + ') OR post_title:(' + q + ') OR post_author:(' + q + ')';}
      var r = jQuery('#{container}').indextank_Renderer({format: fmt, setupContainer: setupContainer, afterRender: afterRender});
      jQuery('#{input}').parents('form').indextank_Ize(INDEXTANK_PUBLIC_URL, INDEXTANK_INDEX_NAME);
      jQuery('#{input}').indextank_Autocomplete().indextank_AjaxSearch({ listeners: r.add(stContainer).add(pContainer), 
                                                                   fields: 'post_title,post_author,timestamp,url,thumbnail,post_content',
                                                                   snippets:'post_content', 
                                                                   rewriteQuery: rw }).indextank_InstantSearch();
    });
    "

    return buff
  
  
  end

end

