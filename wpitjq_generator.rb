#!/usr/bin/env ruby

require 'nokogiri'
require 'date'
require 'open-uri'
require 'logger'

class DummyNode
  def text
    ""
  end
end

class Generator 

  def initialize
    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG
  end

  # for a given list of nodes, computes the common parent.
  # as this nodes are all part of the same tree, 
  # they MUST have a common parent (or one of them be the root)
  def common_parent(nodes)
    ancestors = nodes.map { |n|  n.ancestors << n }
    return ancestors.reduce(:&).first
  end


  def is_author_node(node)

    # what to seek on every attribute.
    # search for:
    #   - author or vcard on 'class'
    #   - author on 'rel'
    special_attrs = { "class" => ['author', 'vcard'],
                      "rel" => ['author']
                    }

    # go up in the hierarchy
    node.ancestors.each do |p|
      special_attrs.each_pair do |attr_name, goals|

        attr = p.attribute(attr_name) || DummyNode.new

        goals.each do |goal|
          if attr.text.index(goal) != nil then
            @log.debug( "#{node} is an author node")
            return true
          end
        end

      end
    end

    # sorry
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
            # check for siblings .. text overrides siblings! 
            if n1.next == nil then
              return ".text(' #{n1.text().strip()} ')"
            else
              return ".append(' #{n1.text().strip()} ')"
            end
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
              end

              # else 
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
        if ( specials["description"].index(n1) || 0 ) >= 0 then
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
    @log.debug "found #{items.length} items"
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


    containers = {}


    # So, for each item we have a mapping from
    # content type => blog node that matches
    paired_items.each_pair do |i, mapping|

      parents = []

      # for each possible title, find the common parent for every description
      mapping["title"].each do |a_title|
        mapping["description"].each do |a_desc|
          parents << common_parent( [a_title, a_desc] )
        end
      end

      parents = parents.sort_by { |n| n.ancestors.size }

      # keep track of the best container, for every item
      containers[i] = parents.last unless parents.empty?
    end



    # ok, so I got for every item a path for its title and description
    # try to find out if there are outliers, and discard them 
    lengths = {}
    containers.values.each do |node| 
      l = node.ancestors.size

      # initialize if needed
      lengths[l] = 0 unless lengths[l]

      # and count
      lengths[l] += 1 
    end

    lengths = lengths.sort {|a,b| a[1] <=> b[1] }
      
    containers.each_pair do |item, prefix|
      # only keep those whose length equals the most likely one 
      containers.delete(item) unless prefix.ancestors.size  == lengths.last.first
    end


    container = common_parent( containers.values )
    input = blog.css("input[name='s']").first

    # verify there was a search box. It may not be the case
    if input == nil then
      print "\tthis theme does NOT have a searchbox!"
      return ""
    end


    if input.attribute("id") then
      input = "##{input.attribute('id')}"
    else 
      input = 'input[name="s"]'
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
    
    # so we got almost everything
    @log.debug paired_items[containers.keys[-1]]
    fmt = traverse(containers.values[-1], containers.values[-2], paired_items[containers.keys[-1]])


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
        $el.children().not('#stats, #paginator, #sorting').detach(); 
      }

      var afterRender = function($el) {
        var p = jQuery('#paginator').detach();
        // send it to the bottom of the results
        $el.append(p);
      }


      // Listeners for indextank_AjaxSearch
      var listeners = jQuery(new Object());

      // create some placeholders
      // - stats
      var stContainer = jQuery('<div/>').attr('id','stats').hide();
      stContainer.append(jQuery('<span/>')); // deal with stats wanting something inside the container, to 'replace'
      stContainer.indextank_StatsRenderer();
      listeners = listeners.add(stContainer);

      // - sorting
      // it may not be present on indextank-wordpress < 1.2 .. check it first
      if (jQuery.fn.indextank_Sorting) { 
        var sortingContainer = jQuery('<div/>').attr('id', 'sorting').hide();
        sortingContainer.indextank_Sorting({labels: {'relevance': 0, 'newest': 1, 'comments': 2 }});
        jQuery('#{container}').prepend(sortingContainer);
        listeners = listeners.add(sortingContainer);

        // sorting controls should appear as soon as a query triggers .. no sooner.
        // fix that
        var sortingVisible = jQuery(new Object()).bind('Indextank.AjaxSearch.success', function(){
          jQuery('#sorting').show();
        });
        listeners = listeners.add(sortingVisible);
      } 


      // - pagination
      var pContainer = jQuery('<div/>').attr('id','paginator').hide();
      pContainer.indextank_Pagination({maxPages:5});
      listeners = listeners.add(pContainer);

      jQuery('#{container}').prepend(stContainer).append(pContainer);

      

      
      var rw = function(q) { 
        if (/[\):]/.test(q)) return q;
        
        //else
        return 'post_content:(' + q + ') OR post_title:(' + q + ') OR post_author:(' + q + ')';
      }
      var r = jQuery('#{container}').indextank_Renderer({format: fmt, setupContainer: setupContainer, afterRender: afterRender});
      listeners = listeners.add(r);
      jQuery('#{input}').parents('form').indextank_Ize(INDEXTANK_PUBLIC_URL, INDEXTANK_INDEX_NAME);
      jQuery('#{input}').indextank_Autocomplete().indextank_AjaxSearch({ listeners: listeners, 
                                                                   fields: 'post_title,post_author,timestamp,url,thumbnail,post_content',
                                                                   snippets:'post_content', 
                                                                   rewriteQuery: rw }).indextank_InstantSearch();
    });
    "

    return buff
  
  
  end

end

