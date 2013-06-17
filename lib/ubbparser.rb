require "strscan"
require "securerandom"
require "cgi"

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

module UBBParser

	# Mapping can be used to allow simplified use of files
	# [img]123123[/img] would have the same effect as [img]files/download/123123[/img]
	#noinspection RubyClassVariableUsageInspection
	def self.set_file_url_convert_method(callback_method)
		@@file_url_convert_method = callback_method
	end

  # Converts a strings containing key-value-list into a hash. This function is mostly used by the parser itself.
  # Attributes are given to the render methods as a hash.
	def self.attrib_str_to_hash(attrib_str)
		result = {:original_attrib_str => attrib_str.gsub(/^=/, "")}

		attrib_str.insert(0, "default") if (attrib_str[0] == "=")
		attrib_str.scan(/((\S*)=(\"[^\"]*\"|\'[^\']*\'|\S*))/) { | all, key, val |
			result[(key.gsub(/-/, "_").to_sym rescue key)] = val.gsub(/^[\"\']/, "").gsub(/[\"\']$/, "")
		}
		return result
	end

  # Converts a hash into a string with key-values. You can use one of the following options:
  # [:allowed_keys]   An array of keys that are only allowed
  # [:denied_keys]    An array of keys that are denied
  # ===Example:
  #   UBBParser.hash_to_attrib_str({}, {:allowed_keys => [:class, :src, :width]})
	def self.hash_to_attrib_str(hash, options = {})
		hash.delete_if { | k, v | !options[:allowed_keys].include?(k) } if options[:allowed_keys].is_a?(Array)
		hash.delete_if { | k, v | options[:denied_keys].include?(k) } if options[:denied_keys].is_a?(Array)
		return hash.map { | k, v | v = v.to_s.gsub(/\\|'/) { |c| "\\#{c}" }; "#{k}='#{v}'" }.join(" ");
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
  def self.parse(text, parse_options = {})
  	result = ""
  	scnr = StringScanner.new(text)
  	parse_options.each { | k, v | v.to_s.gsub(/-/, "_").gsub(/[^\w]+/, "") if (k.to_s.start_with?("class_")); v }
		while (!scnr.eos?)
			untagged_text = CGI.escapeHTML(scnr.scan(/[^\[]*/))

			# convert newlines to breaks
			untagged_text.gsub!(/\n/, "<br />") if (!parse_options.include?(:convert_newlines) || parse_options[:convert_newlines])

			# check for untagged url's
			uri_pattern = /(((http|https|ftp)\:\/\/)|(www))[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,4}(:[a-zA-Z0-9]*)?\/?([a-zA-Z0-9\-\._\?\,\'\/\\\+&amp;%\$#\=~])*[^\.\,\)\(\s]*/
			untagged_text.gsub!(uri_pattern) { | url, | render_url(url, {}, parse_options) }

			# check for untagged emails
			email_pattern = /(([a-zA-Z0-9_\-\.\+]+)@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.)|(([a-zA-Z0-9\-]+\.)+))([a-zA-Z]{2,4}|[0-9]{1,3})(\]?))/
			untagged_text.gsub!(email_pattern) { | email, | render_email(email, {}, parse_options) }

			result << untagged_text

			# check for the upcoming ubb tag and process it (if valid tag)
			if (scnr.match?(/\[/))
				scnr.skip(/\[/)
				code = scnr.scan(/[\w-]*/)
				method_name = ("render_" + code.to_s.gsub(/-/, "_")).to_sym
				if ((scnr.eos?) || (code == "") || (!self.respond_to?(method_name)))
					result << "[" + code
				else
					attributes = self.attrib_str_to_hash(scnr.scan(/[^\]]*/))
					scnr.skip(/\]/)
					inner_text = scnr.scan_until(/\[\/#{code}\]/)
					if inner_text.nil? #no closing tag found
						inner_text = scnr.rest
						scnr.terminate
					else
						inner_text.chomp!("[/#{code}]")
					end
					method_result = self.send(method_name, inner_text, attributes, parse_options).to_s
					result << method_result
				end
			end
		end
		return result
  end

	# Returns true if the given value matches the given regular expression.
  # :category: Validation methods
  def self.matches_regexp?(value, regexp)
    return !value.to_s.match(regexp).nil?
  end

	# Returns true if the given value is a valid email address
  # :category: Validation methods
  def self.is_email?(value)
    return false if !value.is_a?(String)
    return self.matches_regexp?(value, /^[-a-z0-9~!$%^&*_=+}{\'?]+(\.[-a-z0-9~!$%^&*_=+}{\'?]+)*@([a-z0-9_][-a-z0-9_]*(\.[-a-z0-9_]+)*\.(aero|arpa|biz|com|coop|edu|gov|info|int|mil|museum|name|net|org|pro|travel|mobi|[a-z][a-z])|([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}))(:[0-9]{1,5})?$/i)
  end

	# Returns true if the given value is a valid url
  # :category: Validation methods
  def self.is_url?(value)
    return self.matches_regexp?(value, /^(http|https)\:\/\/([a-zA-Z0-9\.\-]+(\:[a-zA-Z0-9\.&amp;%\$\-]+)*@)*((25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9])\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[0-9])|localhost|([a-zA-Z0-9\-]+\.)*[a-zA-Z0-9\-]+\.(com|edu|gov|int|mil|net|org|biz|arpa|info|name|pro|aero|coop|museum|[a-zA-Z]{2}))(\:[0-9]+)*(\/($|[a-zA-Z0-9\.\,\?\'\\\+&amp;%\$#\=~_\-]+))*$/)
  end

	# Converts the [anchor=myname]...[/anchor] tag into <a name='myname'>...</a>. Use the :class_anchor parse option to define html classes.
  # :category: Render methods
	def self.render_anchor(inner_text, attributes = {}, parse_options = {})
		name = attributes[:default] || ""
		name.inner_text.gsub!(/\\|'/) { |c| "\\#{c}" }
  	"<a name='#{name}' class='#{parse_options[:class_anchor].to_s.strip}'>#{self.parse(inner_text, parse_options)}</a>"
	end

	# Converts the url in the inner_text into a webplayer, playing the audio file.
  # :category: Render methods
	def self.render_audio(inner_text, attributes = {}, parse_options = {})
		# Not yet implemented
	end

  # Renders the inner_text bold (using <strong>).
  # :category: Render methods
	def self.render_b(inner_text, attributes = {}, parse_options = {})
  	"<strong>#{self.parse(inner_text, parse_options)}</strong>"
	end

  # Converts [br] into a <br />.
  # :category: Render methods
	def self.render_br(inner_text, attributes = {}, parse_options = {})
  	"<br />#{self.parse(inner_text, parse_options)}"
	end

	# Converts all lines in the inner_text as a bullet list. Each line represents one list item. Empty lines are ignored. Use the :class_bullet parse option to define html classes.
  # :category: Render methods
	def self.render_bullets(inner_text, attributes = {}, parse_options = {})
		items = inner_text.split(/\n/)
		items.delete_if { | item | item.strip == "" }
		items.map! { | item | "<li>" + self.parse(item, parse_options) + "</li>" }
		return (items.empty?) ? "" : "<ul class='#{parse_options[:class_list].to_s.strip}'>" + items.join("") + "</ul>"
	end

	# Centers the inner_text.
  # :category: Render methods
	def self.render_center(inner_text, attributes = {}, parse_options = {})
  	"<div style='text-align: center'>#{self.parse(inner_text, parse_options)}</div>"
	end

	# Assures the inner_text is rendered below floating elements.
  # :category: Render methods
	def self.render_clear(inner_text, attributes = {}, parse_options = {})
  	"<div style='clear: both'></div>"
	end

	# Changes the font color of the inner_text
  # :category: Render methods
	def self.render_color(inner_text, attributes = {}, parse_options = {})
  	"<div style='color:#{attributes[:default]}'>#{self.parse(inner_text, parse_options)}</div>"
	end

	#	Ignores all the inner_text
  # :category: Render methods
	def self.render_comment(inner_text, attributes = {}, parse_options = {})
		""
	end

	# Places the inner_text in a fixed font type. Also adds the classes prettify and linenums for styling purposes. Use the :class_code parse option to define html classes.
  # :category: Render methods
	def self.render_code(inner_text, attributes = {}, parse_options = {})
		"<pre class='#{parse_options[:class_code].to_s.strip}'>#{inner_text}</pre>"
	end

	# Renders csv-data into a html table. You can use the following attributes:
	# [:has_header]  The first row should be rendered as header cells (using th).
  # :category: Render methods
	def self.render_csv(inner_text, attributes = {}, parse_options = {})
		head_cells = body_cells = ""
		cell_tag = (attributes[:has_header] || true) ? "th" : "td"
		lines = inner_text.split(/\n/)
		csv_pattern = /(\"[^\"]*\"|\'[^\']*\'|[^\n\r,]+)[,\n]?/
		lines.each { | line |
			cells = attrib_str.scan(csv_pattern) { | item | "<#{cell_tag}>#{item}</#{cell_tag}>" }
			cells = "<tr>#{cells}</tr>"
			if (cell_tag == "th")
				head_cells += cells
			else
				body_cells += cells
			end
			cell_tag = "td"
		}
		result = ""
		if (!head_cells.empty? || !body_cells.empty?)
			result = "<table class='#{parse_options[:class_csv].to_s.strip}'>"
			result += "<thead>#{head_cells}</thead>" if (!head_cells.empty?)
			result += "<tbody>#{body_cells}</tbody>"
			result = "</table>"
		end
		return result
	end

	# Renders an email address. There are two options to define:
	#    [email]info@osingasoftware.nl[/email]
	#    [email=info@osingasoftware.nl]Osinga Software[/email]
	# By default the email address is protected against spoofing, using JavaScript. Use the :class_email parse option to define html classes.
  # :category: Render methods
	def self.render_email(inner_text, attributes = {}, parse_options = {})
  	email = (attributes[:default] || inner_text)
  	if (!self.is_email?(email))
  	  parse_options[:class_email] = parse_options[:class_email].to_s + " ubbparser-error"
    	result = "<span class='#{parse_options[:class_email].to_s.strip}'>UBB error: invalid email address #{email}</span>"
    elsif ((parse_options.has_key?(:protect_email) && !parse_options[:protect_email]) || (attributes[:protected] == "false"))
    	result = "<a href='mailto:#{email}' class='#{parse_options[:class_email].to_s.strip}'>#{inner_text}</a>"
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
			script = "<script type='text/javascript'>obj=document.getElementById(\"#{id}\");email=obj.getAttribute(\"data-username\")+\"@\"+obj.getAttribute(\"data-domain\");obj.href=\"mailto:\"+email;obj.innerHTML=#{js_title}</script>";
			result = "<a id='#{id}' class='#{parse_options[:class_email].to_s.strip}' href='#' data-username='#{username}' data-domain='#{domain}'>#{title}</a>#{script}"
    end
  	return result
	end

	# Renders the inner_text in the specified list. The list should contain CSS style font-families, i.e.:
	#   [font=Arial, Helvetica, Sans]...[/font]
  # :category: Render methods
	def self.render_font(inner_text, attributes = {}, parse_options = {})
		font = attributes[:original_attrib_str].gsub!(/\\|'/) { |c| "\\#{c}" }
		"<span style='font-family: #{font}'>#{self.parse(inner_text, parse_options)}</span>"
	end

  # Renders the inner_text in a H1 heading.
  # :category: Render methods
	def self.render_h1(inner_text, attributes = {}, parse_options = {})
		"<h1>#{self.parse(inner_text, parse_options)}</h1>"
	end

  # Renders the inner_text in a H2 heading.
  # :category: Render methods
	def self.render_h2(inner_text, attributes = {}, parse_options = {})
		"<h2>#{self.parse(inner_text, parse_options)}</h2>"
	end

  # Renders the inner_text in a H3 heading.
  # :category: Render methods
	def self.render_h3(inner_text, attributes = {}, parse_options = {})
		"<h3>#{self.parse(inner_text, parse_options)}</h3>"
	end

  # Renders a horizontal ruler.
  # :category: Render methods
	def self.render_hr(inner_text, attributes = {}, parse_options = {})
		"<hr />#{self.parse(inner_text, parse_options)}"
	end

  # Renders the inner_text in italic.
  # :category: Render methods
	def self.render_i(inner_text, attributes = {}, parse_options = {})
  	"<em>#{self.parse(inner_text, parse_options)}</em>"
	end

  # Renders an iframe. Use the inner_text as source. Use the :class_iframe parse option to define html classes.
  # :category: Render methods
	def self.render_iframe(inner_text, attributes = {}, parse_options = {})
  	src = inner_text
  	src = "http://" + src if (src.match(/^www\./))
		src.gsub!(/\\|'/) { |c| "\\#{c}" }
  	attributes[:src] = inner_text
		attributes[:class] = (attributes[:class].to_s + " " + parse_options[:class_iframe].to_s).strip if ((!attributes.has_key?(:skip_class)) || !attributes[:skip_class])
  	attrib_str = self.hash_to_attrib_str(attributes, :allowed_keys => [:src, :class, :frameborder, :marginwidth, :marginheight, :width, :height])
  	return "<iframe #{attrib_str}></iframe>"
	end

	# Doesn't render the ubb code in the inner_text. It does strip all html-tags from the inner_text
  # :category: Render methods
	def self.render_ignore(inner_text, attributes = {}, parse_options = {})
		inner_text
	end

	# Renders an image. Use the :class_img parse option to define html classes.
  # :category: Render methods
  #noinspection RubyClassVariableUsageInspection
	def self.render_img(inner_text, attributes = {}, parse_options = {})
		url = inner_text
		url = @@file_url_convert_method.call(url) unless @@file_url_convert_method.nil?
		attributes[:src] = url.gsub(/\\|'/) { |c| "\\#{c}" }
		attributes[:alt] ||= ""
		attributes[:class] = parse_options[:class_img] if ((!attributes.has_key?(:skip_class)) || !attributes[:skip_class])
		attrib_str = self.hash_to_attrib_str(attributes, :allowed_keys => [:src, :alt, :styles, :class])
		return "<img #{attrib_str} />"
	end

	# Renders an image, floated on the left side of the text frame. Use the :class_img_left parse option to define html classes.
  # :category: Render methods
	def self.render_img_left(inner_text, attributes = {}, parse_options = {})
	  attributes[:styles] = "float: left; margin: 0px 10px 10px 0px"
	  attributes[:class] += " " + parse_options[:class_img_left]
	  attributes[:skip_class] = true
		render_img(inner_text, attributes, parse_options)
	end

	# Renders an image, floated on the right side of the text frame. Use the :class_img_right parse option to define html classes.
  # :category: Render methods
	def self.render_img_right(inner_text, attributes = {}, parse_options = {})
	  attributes[:styles] = "float: left; margin: 0px 0px 10px 10px"
	  attributes[:class] += " " + parse_options[:class_img_right]
	  attributes[:skip_class] = true
		render_img(inner_text, attributes, parse_options)
	end

	# Renders the inner_text with a justified text alignment.
  # :category: Render methods
	def self.render_justify(inner_text, attributes = {}, parse_options = {})
		"<div style='text-align: justify'>#{self.parse(inner_text, parse_options)}</div>"
	end

	# Renders the inner_text with a left text alignment.
  # :category: Render methods
	def self.render_left(inner_text, attributes = {}, parse_options = {})
		"<div style='text-align: left'>#{self.parse(inner_text, parse_options)}</div>"
	end

	# Renders the inner_text as an ordered list. Each line represents a list item. Use the :class_list parse option to define html classes.
  # :category: Render methods
	def self.render_list(inner_text, attributes = {}, parse_options = {})
		items = inner_text.split(/\n/)
		items.delete_if { | item | item.strip == "" }
		items.map! { | item | "<li>" + self.parse(item, parse_options) + "</li>" }
		return (items.empty?) ? "" : "<ol class='#{parse_options[:class_list].to_s.strip}'>" + items.join("") + "</ol>"
	end

	# Renders the inner_text as a paragraph. Use the :class_p parse option to define html classes.
  # :category: Render methods
	def self.render_p(inner_text, attributes = {}, parse_options = {})
		"<p class='#{parse_options[:class_p].to_s.strip}'>#{self.parse(inner_text, parse_options)}</p>"
	end

	# Renders the inner_text with a right text alignment.
  # :category: Render methods
	def self.render_right(inner_text, attributes = {}, parse_options = {})
		"<div style='text-align: right'>#{self.parse(inner_text, parse_options)}</div>"
	end

	# Renders the inner_text in a <div> block with inline CSS styles, i.e.:
	#    [style color: red; border: 1px solid green]...[/style]
  # :category: Render methods
	def self.render_style(inner_text, attributes = {}, parse_options = {})
		styles = attributes[:original_attrib_str].gsub(/'/, "\'")
		"<div style='#{styles}'>#{self.parse(inner_text, parse_options)}</div>"
	end

	# Converts the [table] to a <table>. Always use this in combination with [tr] and [td] or [th]. Use the :class_table parse option to define html classes.
  # :category: Render methods
	def self.render_table(inner_text, attributes = {}, parse_options = {})
		"<table class='#{parse_options[:class_table].to_s.strip}'>#{self.parse(inner_text.gsub(/(^\n+)|(\n+$)/, ""), parse_options)}</table>"
	end

	# Converts the [td] to a <td>. Always use this in combination with [table] and [tr].
  # :category: Render methods
	def self.render_td(inner_text, attributes = {}, parse_options = {})
		"<td>#{self.parse(inner_text, parse_options)}</td>"
	end

	# Converts the [th] to a <th>. Always use this in combination with [table] and [tr].
  # :category: Render methods
	def self.render_th(inner_text, attributes = {}, parse_options = {})

		"<th>#{self.parse(inner_text, parse_options)}</th>"
	end

	# Converts the [tr] to a <tr>. Always use this in combination with [table] and [td] or [th].
  # :category: Render methods
	def self.render_tr(inner_text, attributes = {}, parse_options = {})
		"<tr>#{self.parse(inner_text.gsub(/(^\n+)|(\n+$)/, ""), parse_options)}</tr>"
	end

	# Renders the inner_text underline. Use this with caution, since underline text is associated with hyperlinks.
  # :category: Render methods
	def self.render_u(inner_text, attributes = {}, parse_options = {})
  	"<u>#{self.parse(inner_text, parse_options)}</u>"
	end

	# Renders a web addres. There are two options to define:
	#   [url]www.osingasoftware.nl[/ur]
	#   [url=www.osingasoftware.nl]Osinga Software[/url]
	# Use the :class_url parse option to define html classes.
  # :category: Render methods
	def self.render_url(inner_text, attributes = {}, parse_options = {})
  	url = (attributes[:default] || inner_text)
  	url = "http://" + url if (url.match(/^www\./))
	  url = @@file_url_convert_method.call(url) unless @@file_url_convert_method.nil?
	  url.gsub!(/\\|'/) { |c| "\\#{c}" }
  	return "<a href='#{url}' class='#{parse_options[:class_url].to_s.strip}'>#{inner_text}</a>"
	end

  # Renders a YouTube video using the video id or url in the inner_text.
  # :category: Render methods
	def self.render_vimeo(inner_text, attributes = {}, parse_options = {})
		attributes[:width] ||= 500
		attributes[:height] ||= 281
		attributes[:class] = parse_options[:class_vimeo]
	  attributes[:skip_class] = true
		videoid = (inner_text.scan(/[0-9]{5,}/).to_a)[0].to_s
		src = "http://player.vimeo.com/video/#{videoid}"
		return render_iframe(src, attributes, parse_options)
	end

  # Renders a YouTube video using the video id or url in the inner_text.
  # :category: Render methods
	def self.render_youtube(inner_text, attributes = {}, parse_options = {})
		attributes[:width] ||= 560
		attributes[:height] ||= 315
		attributes[:class] = parse_options[:class_youtube]
	  attributes[:skip_class] = true
		videoid = !inner_text.match(/^[^\?\&]$/).nil? ? inner_text : inner_text.scan(/(\?|&)v=([^\&]*)/)[0][1]
		src = "http://www.youtube.com/embed/#{videoid}"
		return render_iframe(src, attributes, parse_options)
	end

  # Renders a Youtube, Vimeo or Zideo video using the video id or url in the inner_text.
  # It automatically determines which video renderer should be used based on the given url.
  # :category: Render methods
	def self.render_video(inner_text, attributes = {}, parse_options = {})
		attributes[:class] = "#{attributes[:class]} #{parse_options[:class_zideo]}"
		url = inner_text
		if !url.match(/zideo\.nl/).nil?
			return self.render_zideo(inner_text, attributes, parse_options)
		elsif (!url.match(/[0-9]{5,}/).nil?) || (!url.match(/vimeo/).nil?)
			return self.render_vimeo(inner_text, attributes, parse_options)
		elsif (!url.match(/youtu/).nil?) || (!url.match(/^[^\?\&]+{11}$/).nil?)
			return self.render_youtube(inner_text, attributes, parse_options)
		else
			return "Unknown video"
		end
	end

  # Renders a zideo.nl video using the video id or url in the inner_text.
  # :category: Render methods
	def self.render_zideo(inner_text, attributes = {}, parse_options = {})
		attributes[:width] ||= 480
		attributes[:height] ||= auto
		attributes[:class] += " " + parse_options[:class_zideo]
	  attributes[:skip_class] = true
		videoid = !inner_text.match(/^\w+$/).nil? ? inner_text : (inner_text.scan(/playzideo\/(\w+)/).to_a)[1].to_s
		src = "http://www.zideo.nl/zideomediaplayer.php?" + inner_text
		return render_iframe(src, attributes, parse_options)
	end

end