require 'strscan'
require 'securerandom'
require 'cgi'

# The UBBParser module converts UBB code into HTML. The parser is flexibel
# and adding new ubb codes is as easy as writing methods.
#
# You can create your own ubbcodes by opening the module UBBParser and adding a method called render_xxx,
# where xxx is your ubb code of choice. The method should have the following arguments:
#   def render_xxx(inner_text, attributes = {}, parse_options = {})
# [inner_text]    Contains the text that's found between the opening and the closing tag.
# [attributes]    A hash containing all the key-value attributes that are given.
# [parse_options] A hash containing the same parse_options that are used when UBBParser.parse() is called.
#
# ===Example
# The following example adds the ubb code \[sup\]...\[/sup], which wraps the inner_text with <sup> tags
#
#   module UBBParser
#     def render_sup(inner_text, attributes = {}, parse_options = {})
#       "<sup>{inner_text}</sup>"
#     end
#   end
#
# When defining new ubb codes with a method and the name contains a dash, replace the dash by an underscore.
# I.e. the ubb code for img-left uses the method render_img_left.

#noinspection RubyUnusedLocalVariable RubyTooManyMethods
module UBBParser

	extend self

	def inline_elements
		%w(a abbr address area audio b cite code del details dfn command datalist em font i iframe img input ins kbd
			 label legend link mark meter nav optgroup option q small select source span strong sub summary sup tbody td time var)
	end

	# Mapping can be used to allow simplified use of files
	# [img]123123[/img] would have the same effect as [img]files/download/123123[/img]
	#noinspection RubyClassVariableUsageInspection
	def set_file_url_convert_method(callback_method)
		@@file_url_convert_method = callback_method
	end

	#noinspection RubyClassVariableUsageInspection
	@@file_url_convert_method = nil

	# Converts a strings containing key-value-list into a hash. This function is mostly used by the parser it
	# Attributes are given to the render methods as a hash.
	def attrib_str_to_hash(attrib_str)
		result = {:class_attrib_str => attrib_str.gsub(/^=/, '')}

		attrib_str.insert(0, 'default') if (attrib_str[0] == '=')
		attrib_str.scan(/((\S*)=("[^"]*"|'[^']*'|\S*))/) { |_, key, val|
			result[(key.gsub(/-/, '_').to_sym rescue key)] = val.gsub(/^["']/, '').gsub(/["']$/, '')
		}
		return result
	end

	# Converts a hash into a string with key-values. You can use one of the following options:
	# [:allowed_keys]   An array of keys that are only allowed
	# [:denied_keys]    An array of keys that are denied
	# ===Example:
	#   UBBParser.hash_to_attrib_str({}, {:allowed_keys => [:class, :src, :width]})
	def hash_to_attrib_str(hash, options = {})
		hash.delete_if { |k, _| !options[:allowed_keys].include?(k) } if options[:allowed_keys].is_a?(Array)
		hash.delete_if { |k, _| options[:denied_keys].include?(k) } if options[:denied_keys].is_a?(Array)
		return hash.map { |k, v| v = v.to_s.gsub(/\\|'/) { |c| "\\#{c}" }; "#{k}='#{v}'" }.join(' ')
	end

	# Parses the given text with ubb code into html. Use parse_options to specify a hash of options:
	# [:convert_newlines]    A boolean whether newlines should be convert into <br /> tags (default: true).
	# [:protect_email]       A boolean whether email addresses should be protected from spoofing using embedded JavaScript.
	# [:class_xxx]           A string with css class(es) that is embedded in the html for the tag xxx. Not all tags supports this.
	#                        Replace a dash in a tag with underscore (i.e. the class for img-left is defined in :class_img_left).
	# ===Example:
	#   {:class_code: "prettify linenums"} => <pre class='prettify linenums'>...</pre>
	#
	# When developing your own tags, you can also define your own parse_options.
	def parse(text, parse_options = {})
		result = ''
		scnr = StringScanner.new(text)
		parse_options.each { |k, v| v.to_s.gsub(/-/, '_').gsub(/[^\w]+/, '') if (k.to_s.start_with?('class_')); v }
		until scnr.eos?
			untagged_text = CGI.escapeHTML(scnr.scan(/[^\[]*/))

			# convert newlines to breaks
			untagged_text.gsub!(/\n/, '<br />') if (!parse_options.include?(:convert_newlines) || parse_options[:convert_newlines])

			# check for untagged url's
			uri_pattern = /(((http|https|ftp)\:\/\/)|(www))[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,4}(:[a-zA-Z0-9]*)?\/?([a-zA-Z0-9\-\._\?\,\'\/\\\+&amp;%\$#\=~])*[^\.\,\)\(\s]*/
			untagged_text.gsub!(uri_pattern) { |url,| render_url(url, {}, parse_options) }

			# check for untagged emails
			email_pattern = /(([a-zA-Z0-9_\-\.\+]+)@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.)|(([a-zA-Z0-9\-]+\.)+))([a-zA-Z]{2,4}|[0-9]{1,3})(\]?))/
			untagged_text.gsub!(email_pattern) { |email,| render_email(email, {}, parse_options) }

			result << untagged_text

			# check for the upcoming ubb tag and process it (if valid tag)
			if scnr.match?(/\[/)
				scnr.skip(/\[/)
				code = scnr.scan(/[\w-]*/)
				method_name = ('render_' + code.to_s.gsub(/-/, '_')).to_sym
				if ((scnr.eos?) || (code == "") || (!respond_to?(method_name)))
					result << '[' + code
				else
					attributes = attrib_str_to_hash(scnr.scan(/[^\]]*/))
					scnr.skip(/]/)
					inner_text = scnr.scan_until(/\[\/#{code}\]/)
					if inner_text.nil? #no closing tag found
						inner_text = scnr.rest
						scnr.terminate
					else
						inner_text.chomp!("[/#{code}]")
					end
					method_result = send(method_name, inner_text, attributes, parse_options).to_s
					result << method_result
					last_html_tag = method_result.match('</(\w+)>$').to_s.gsub(/[^\w]/, '')
					scnr.skip(/\n?/) unless (inline_elements.include?(last_html_tag)) # Skip next newline if last tag was not inline element
				end
			end
		end
		return result
	end

	# Returns true if the given value matches the given regular expression.
	# :category: Validation methods
	def matches_regexp?(value, regexp)
		return !value.to_s.match(regexp).nil?
	end

	# Returns true if the given value is a valid email address
	# :category: Validation methods
	def is_email?(value)
		return false unless value.is_a?(String)
		return matches_regexp?(value, /^[-a-z0-9~!$%^&*_=+}{\'?]+(\.[-a-z0-9~!$%^&*_=+}{\'?]+)*@([a-z0-9_][-a-z0-9_]*(\.[-a-z0-9_]+)*\.(aero|arpa|biz|com|coop|edu|gov|info|int|mil|museum|name|net|org|pro|travel|mobi|[a-z][a-z])|([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}))(:[0-9]{1,5})?$/i)
	end

	# Returns true if the given value is a valid url
	# :category: Validation methods
	def is_url?(value)
		return matches_regexp?(value, /^(http|https)\:\/\/([a-zA-Z0-9\.\-]+(\:[a-zA-Z0-9\.&amp;%\$\-]+)*@)*((25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9])\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1][0-9]{2}|[1-9][0-9]|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1][0-9]{2}|[1-9][0-9]{1}|[0-9])|localhost|([a-zA-Z0-9\-]+\.)*[a-zA-Z0-9\-]+\.(com|edu|gov|int|mil|net|org|biz|arpa|info|name|pro|aero|coop|museum|[a-zA-Z]{2}))(:[0-9]+)*(\/($|[a-zA-Z0-9\.\,\?\'\\\+&amp;%\$#\=~_\-]+))*$/)
	end

	# Converts the [anchor=myname]...[/anchor] tag into <a name='myname'>...</a>. Use the :class_anchor parse option to define html classes.
	# :category: Render methods
	def render_anchor(inner_text, attributes = {}, parse_options = {})
		name = attributes[:default] || ''
		inner_text.gsub!(/\\|'/) { |c| "\\#{c}" }
		css_class = parse_options[:class_anchor] || 'ubb-anchor'
		"<a name='#{name}' class='#{css_class}'>#{parse(inner_text, parse_options)}</a>"
	end

	# Converts the url in the inner_text into a webplayer, playing the audio file.
	# :category: Render methods
	def render_audio(inner_text, attributes = {}, parse_options = {})
		# Not yet implemented
	end

	# Renders the inner_text bold (using <strong>).
	# :category: Render methods
	def render_b(inner_text, attributes = {}, parse_options = {})
		"<strong>#{parse(inner_text, parse_options)}</strong>"
	end

	# Converts [br] into a <br />.
	# :category: Render methods
	def render_br(inner_text, attributes = {}, parse_options = {})
		"<br />#{parse(inner_text, parse_options)}"
	end

	# Converts all lines in the inner_text as a bullet list. Each line represents one list item. Empty lines are ignored. Use the :class_bullet parse option to define html classes.
	# :category: Render methods
	def render_bullets(inner_text, attributes = {}, parse_options = {})
		items = inner_text.split(/\n/)
		items.delete_if { |item| item.strip == '' }
		items.map! { |item| '<li>' + parse(item, parse_options) + '</li>' }
		css_class = parse_options[:class_list] || 'ubb-list'
		return (items.empty?) ? '' : "<ul class='#{css_class}'>" + items.join('') + '</ul>'
	end

	# Centers the inner_text.
	# :category: Render methods
	def render_center(inner_text, attributes = {}, parse_options = {})
		"<div style='text-align: center'>#{parse(inner_text, parse_options)}</div>"
	end

	# Assures the inner_text is rendered below floating elements.
	# :category: Render methods
	def render_class(inner_text, attributes = {}, parse_options = {})
		classes = attributes[:class_attrib_str].to_s.gsub(/'/, "\\'")
		"<div class='#{classes}'>#{parse(inner_text, parse_options)}</div>"
	end

	# Assures the inner_text is rendered below floating elements.
	# :category: Render methods
	def render_clear(inner_text, attributes = {}, parse_options = {})
		"<div style='clear: both'></div>"
	end

	# Changes the font color of the inner_text
	# :category: Render methods
	def render_color(inner_text, attributes = {}, parse_options = {})
		color = attributes[:default].gsub(/'/, "\\'")
		"<div style='color:#{color}'>#{parse(inner_text, parse_options)}</div>"
	end

	#	Ignores all the inner_text
	# :category: Render methods
	def render_comment(inner_text, attributes = {}, parse_options = {})
		''
	end

	# Places the inner_text in a fixed font type. Also adds the classes prettify and linenums for styling purposes. Use the :class_code parse option to define html classes.
	# :category: Render methods
	def render_code(inner_text, attributes = {}, parse_options = {})
		css_class = parse_options[:class_code] || 'ubb-code'
		"<pre class='#{css_class}'>#{inner_text}</pre>"
	end

	# Renders csv-data into a html table. You can use the following attributes:
	# [:has_header]  The first row should be rendered as header cells (using th).
	# :category: Render methods
	def render_csv(inner_text, attributes = {}, parse_options = {})
		head_cells = body_cells = ''
		cell_tag = (attributes[:has_header]) ? 'th' : 'td'
		lines = inner_text.gsub(/(^\n|\n*$)/, '').split(/\n/)
		sep_char = (attributes[:sepchar] || ',')
		csv_pattern = /(\"[^\"]*\"|\'[^\']*\'|[^\n\r#{sep_char}]+)[#{sep_char}\n]?/
		lines.each { |line|
			cells = ''
			line.scan(csv_pattern) { |item|
				cells += "<#{cell_tag}>#{item[0]}</#{cell_tag}>"
			}
			cells = "<tr>#{cells}</tr>"
			if cell_tag == 'th'
				head_cells += cells
			else
				body_cells += cells
			end
			cell_tag = 'td'
		}
		result = ''
		if !head_cells.empty? || !body_cells.empty?
			css_class = parse_options[:class_csv] || 'ubb-csv ubb-table'
			result = "<table class='#{css_class}'>"
			result += "<thead>#{head_cells}</thead>" unless head_cells.empty?
			result += "<tbody>#{body_cells}</tbody>"
			result += '</table>'
		end
		return result
	end

	# Renders an email address. There are two options to define:
	#    [email]info@osingasoftware.nl[/email]
	#    [email=info@osingasoftware.nl]Osinga Software[/email]
	# By default the email address is protected against spoofing, using JavaScript. Use the email parse option to define html classes.
	# :category: Render methods
	def render_email(inner_text, attributes = {}, parse_options = {})
		css_class = (parse_options[:class_email] || 'ubb-email').to_s.strip
		inner_text = parse(inner_text, parse_options) if !attributes[:default].nil?
  	email = (attributes[:default] || inner_text)
  	if (!is_email?(email))
    	result = "<span class='#{css_class} ubbparser-error'>UBB error: invalid email address #{email}</span>"
    elsif ((parse_options.has_key?(:protect_email) && !parse_options[:protect_email]) || (attributes[:protected] == "false"))
    	result = "<a href='mailto:#{email}' class='#{css_class}'>#{inner_text}</a>"
    else
    	username, domain = email.split("@", 2)
    	id = "ubb-email-" + SecureRandom.hex(16)

    	# Some generic javascript so every browser can parse this (instantly), regardless of used framework
    	if (inner_text == email)
		    title = "Protected email address"
		    js_title = "email"
	    else
				title = inner_text
				js_title = "\"#{inner_text}\""
			end
			script = "<script type='text/javascript'>obj=document.getElementById(\"#{id}\");email=obj.getAttribute(\"data-username\")+\"@\"+obj.getAttribute(\"data-domain\");obj.href=\"mailto:\"+email;obj.innerHTML=#{js_title}</script>"
			result = "<a id='#{id}' class='#{css_class}' href='#' data-username='#{username}' data-domain='#{domain}'>#{title}</a>#{script}"
		end
		return result
	end

	# Renders the inner_text in a H1 heading.
	# :category: Render methods
	def render_h1(inner_text, attributes = {}, parse_options = {})
		"<h1>#{parse(inner_text, parse_options)}</h1>"
	end

	# Renders the inner_text in a H2 heading.
	# :category: Render methods
	def render_h2(inner_text, attributes = {}, parse_options = {})
		"<h2>#{parse(inner_text, parse_options)}</h2>"
	end

	# Renders the inner_text in a H3 heading.
	# :category: Render methods
	def render_h3(inner_text, attributes = {}, parse_options = {})
		"<h3>#{parse(inner_text, parse_options)}</h3>"
	end

	# Renders the inner_text in a H4 heading.
	# :category: Render methods
	def render_h4(inner_text, attributes = {}, parse_options = {})
		"<h4>#{parse(inner_text, parse_options)}</h4>"
	end

	# Renders the inner_text in a H5 heading.
	# :category: Render methods
	def render_h5(inner_text, attributes = {}, parse_options = {})
		"<h5>#{parse(inner_text, parse_options)}</h5>"
	end

	# Renders the inner_text in a H6 heading.
	# :category: Render methods
	def render_h6(inner_text, attributes = {}, parse_options = {})
		"<h6>#{parse(inner_text, parse_options)}</h6>"
	end

	# Renders a horizontal ruler.
	# :category: Render methods
	def render_hr(inner_text, attributes = {}, parse_options = {})
		"<hr />#{parse(inner_text, parse_options)}"
	end

	# Renders the inner_text in italic.
	# :category: Render methods
	def render_i(inner_text, attributes = {}, parse_options = {})
		"<em>#{parse(inner_text, parse_options)}</em>"
	end

	# Renders an iframe. Use the inner_text as source. Use the :class_iframe parse option to define html classes.
	# :category: Render methods
	def render_iframe(inner_text, attributes = {}, parse_options = {})
		src = inner_text
		src = 'http://' + src if (src.match(/^www\./))
		src.gsub!(/\\|'/) { |c| "\\#{c}" }
		attributes[:src] = inner_text
		attributes[:class] = attributes[:class] || parse_options[:class_iframe] || 'ubb-iframe'
		attrib_str = hash_to_attrib_str(attributes, :allowed_keys => [:src, :class, :frameborder, :marginwidth, :marginheight, :width, :height])
		return "<iframe #{attrib_str}></iframe>"
	end

	# Doesn't render the ubb code in the inner_text. It does strip all html-tags from the inner_text
	# :category: Render methods
	def render_ignore(inner_text, attributes = {}, parse_options = {})
		inner_text
	end

	# Renders an image. Use the :class_img parse option to define html classes.
	# :category: Render methods
	#noinspection RubyClassVariableUsageInspection
	def render_img(inner_text, attributes = {}, parse_options = {})
		url = inner_text
		url = @@file_url_convert_method.call(url) unless @@file_url_convert_method.nil?
		attributes[:src] = url.gsub(/\\|'/) { |c| "\\#{c}" }
		attributes[:alt] ||= ''

		attributes[:class] = attributes[:class] || parse_options[:class] || 'ubb-img'
		attrib_str = hash_to_attrib_str(attributes, :allowed_keys => [:src, :alt, :styles, :class])
		return "<img #{attrib_str} />"
	end

	# Renders an image, floated on the left side of the text frame. Use the :class_img_left parse option to define html classes.
	# :category: Render methods
	def render_img_left(inner_text, attributes = {}, parse_options = {})
		attributes[:styles] = 'float: left; margin: 0px 10px 10px 0px'
		attributes[:class] = parse_options[:class_img_left] || 'ubb-img-left'
		render_img(inner_text, attributes, parse_options)
	end

	# Renders an image, floated on the right side of the text frame. Use the :class_img_right parse option to define html classes.
	# :category: Render methods
	def render_img_right(inner_text, attributes = {}, parse_options = {})
		attributes[:styles] = 'float: left; margin: 0px 0px 10px 10px'
		attributes[:class] = parse_options[:class_img_right] || 'ubb-img-right'
		render_img(inner_text, attributes, parse_options)
	end

	# Renders the inner_text with a justified text alignment.
	# :category: Render methods
	def render_justify(inner_text, attributes = {}, parse_options = {})
		"<div style='text-align: justify'>#{parse(inner_text, parse_options)}</div>"
	end

	# Renders the inner_text with a left text alignment.
	# :category: Render methods
	def render_left(inner_text, attributes = {}, parse_options = {})
		"<div style='text-align: left'>#{parse(inner_text, parse_options)}</div>"
	end

	# Renders the inner_text as an ordered list. Each line represents a list item. Use the :class_list parse option to define html classes.
	# :category: Render methods
	def render_list(inner_text, attributes = {}, parse_options = {})
		items = inner_text.split(/\n/)
		items.delete_if { |item| item.strip == '' }
		items.map! { |item| '<li>' + parse(item, parse_options) + '</li>' }
		return (items.empty?) ? '' : "<ol class='#{parse_options[:class_list].to_s.strip}'>" + items.join('') + '</ol>'
	end

	# Renders the inner_text as a paragraph. Use the :class_p parse option to define html classes.
	# :category: Render methods
	def render_p(inner_text, attributes = {}, parse_options = {})
		css_class = parse_options[:class_p] || 'ubb-p'
		"<p class='#{css_class}'>#{parse(inner_text, parse_options)}</p>"
	end

	# Renders the inner_text with a right text alignment.
	# :category: Render methods
	def render_right(inner_text, attributes = {}, parse_options = {})
		"<div style='text-align: right'>#{parse(inner_text, parse_options)}</div>"
	end

	# Renders the inner_text in a <div> block with inline CSS styles, i.e.:
	#    [style color: red; border: 1px solid green]...[/style]
	# :category: Render methods
	def render_style(inner_text, attributes = {}, parse_options = {})
		styles = attributes[:class_attrib_str].to_s.gsub(/'/, "\\'")
		"<div style='#{styles}'>#{parse(inner_text, parse_options)}</div>"
	end

	# Converts the [table] to a <table>. Always use this in combination with [tr] and [td] or [th]. Use the :class_table parse option to define html classes.
	# :category: Render methods
	def render_table(inner_text, attributes = {}, parse_options = {})
		css_class = parse_options[:class_table] || 'ubb-table'
		"<table class='#{css_class}'>#{parse(inner_text.gsub(/(^\n+)|(\n+$)/, ''), parse_options)}</table>"
	end

	# Converts the [td] to a <td>. Always use this in combination with [table] and [tr].
	# :category: Render methods
	def render_td(inner_text, attributes = {}, parse_options = {})
		"<td>#{parse(inner_text, parse_options)}</td>"
	end

	# Converts the [th] to a <th>. Always use this in combination with [table] and [tr].
	# :category: Render methods
	def render_th(inner_text, attributes = {}, parse_options = {})
		"<th>#{parse(inner_text, parse_options)}</th>"
	end

	# Converts the [tr] to a <tr>. Always use this in combination with [table] and [td] or [th].
	# :category: Render methods
	def render_tr(inner_text, attributes = {}, parse_options = {})
		"<tr>#{parse(inner_text.gsub(/(^\n+)|(\n+$)/, ''), parse_options)}</tr>"
	end

	# Renders the inner_text underline. Use this with caution, since underline text is associated with hyperlinks.
	# :category: Render methods
	def render_u(inner_text, attributes = {}, parse_options = {})
		"<u>#{parse(inner_text, parse_options)}</u>"
	end

	# Renders a web addres. There are two options to define:
	#   [url]www.osingasoftware.nl[/ur]
	#   [url=www.osingasoftware.nl]Osinga Software[/url]
	# Use the :class_url parse option to define html classes.
	# :category: Render methods
	#noinspection RubyClassVariableUsageInspection
	def render_url(inner_text, attributes = {}, parse_options = {})
		inner_text = parse(inner_text, parse_options) if !attributes[:default].nil?
		url = (attributes[:default] || inner_text)
		url = 'http://' + url if (url.start_with?('www.'))
		target = (url.start_with?('http://')) ? " target='_blank'" : ''
		url = @@file_url_convert_method.call(url) unless @@file_url_convert_method.nil?
		url.to_s.gsub!(/\\|'/) { |c| "\\#{c}" }
		css_class = parse_options[:class_url] || 'ubb-url'
		return "<a href='#{url}' class='#{css_class}'#{target}>#{inner_text}</a>"
	end

	# Renders a YouTube video using the video id or url in the inner_text.
	# :category: Render methods
	def render_vimeo(inner_text, attributes = {}, parse_options = {})
		attributes[:width] ||= 500
		attributes[:height] ||= 281
		attributes[:class] = parse_options[:class_vimeo] || 'ubb-vimeo'
		video_id = (inner_text.scan(/[0-9]{5,}/).to_a)[0].to_s
		src = "http://player.vimeo.com/video/#{video_id}"
		return render_iframe(src, attributes, parse_options)
	end

	# Renders a YouTube video using the video id or url in the inner_text.
	# :category: Render methods
	def render_youtube(inner_text, attributes = {}, parse_options = {})
		attributes[:width] ||= 560
		attributes[:height] ||= 315
		attributes[:class] = parse_options[:class_youtube] || 'ubb-youtube'
		videoid = !inner_text.match(/^[^\?\&]$/).nil? ? inner_text : inner_text.scan(/(\?|&)v=([^\&]*)/)[0][1]
		src = "http://www.youtube.com/embed/#{videoid}"
		return render_iframe(src, attributes, parse_options)
	end

	# Renders a Youtube, Vimeo or Zideo video using the video id or url in the inner_text.
	# It automatically determines which video renderer should be used based on the given url.
	# :category: Render methods
	def render_video(inner_text, attributes = {}, parse_options = {})
		attributes[:class] = "#{attributes[:class]} #{parse_options[:class_zideo]}"
		url = inner_text
		if !url.match(/zideo\.nl/).nil?
			return render_zideo(inner_text, attributes, parse_options)
		elsif (!url.match(/[0-9]{5,}/).nil?) || (!url.match(/vimeo/).nil?)
			return render_vimeo(inner_text, attributes, parse_options)
		elsif (!url.match(/youtu/).nil?) || (!url.match(/^[^\?&]+\{11}$/).nil?)
			return render_youtube(inner_text, attributes, parse_options)
		else
			return 'Unknown video'
		end
	end

	# Renders a zideo.nl video using the video id or url in the inner_text.
	# :category: Render methods
	def render_zideo(inner_text, attributes = {}, parse_options = {})
		attributes[:width] ||= 480
		attributes[:height] ||= :auto
		attributes[:class] = parse_options[:class_zideo] || 'ubb-zideo'
		video_id = !inner_text.match(/^\w+$/).nil? ? inner_text : (inner_text.scan('/playzideo/(\w+)/').to_a)[1].to_s
		src = 'http://www.zideo.nl/zideomediaplayer.php?' + video_id
		return render_iframe(src, attributes, parse_options)
	end

end