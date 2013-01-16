UBBParser
=========

A Ruby Gem which parse ubb code to html. The documentation can be found on http://ubbparser.mojura.nl.

After installing the gem use the following code:

    require 'ubbparser'
    UBBParser.parse("This is an [b]example[/b]")
    # Result => "This is an <b>example</b>"
    

The parse method allow a second parameter parse_options. It's an hash containing a few options.
- :convert_newlines   => A boolean whether newlines should be convert into \<br /> tags (default: true).
- :protect_email      => A boolean whether email addresses should be protected from spoofing using embedded JavaScript (default: true).
- :class_xxx          => A string with css class(es) that are embedded in the html attribute class='' for the tag xxx. Not all tags supports this.

Example:

    require 'ubbparser'
    UBBParser.parse("Check the website [url]http://ubbparser.mojura.nl[/url]", {:class_ubb => "my_url_class"})
    # Result => "Check the website <a href='http://ubbparser.mojura.nl' class='my_url_class'>http://ubbparser.mojura.nl</a>"
