$:.unshift File.join(File.dirname(__FILE__), "..")
require "test/unit"
require "lib/ubbparser"

# The UBBParserTester is the unit test for the UBB Parser.
class UBBParserTester < Test::Unit::TestCase

 def test_in_array
  assert_equal("This is a <strong>test</strong>",
               UBBParser.parse("This is a [b]test[/b]"))
               
  assert_equal("<strong>test</strong>",
               UBBParser.parse("[b]test[/b]"))
               
  assert_equal("This is a <strong><em>test</em></strong>",
               UBBParser.parse("This is a [b][i]test[/i][/b]"))
               
  assert_equal("This is a <strong><em>test</em></strong>[/i]",
               UBBParser.parse("This is a [b][i]test[/b][/i]"))
               
  assert_equal("just [something] unknown",
               UBBParser.parse("just [something] unknown"))
               
  assert_equal("<a href='http://www.mojura.nl' class=''>http://www.mojura.nl</a>",
               UBBParser.parse("[url]http://www.mojura.nl[/url]"))
               
  assert_equal("<a href='http://www.mojura.nl' class=''>http://www.mojura.nl</a>",
               UBBParser.parse("http://www.mojura.nl"))
               
  assert_equal("<a href='http://www.mojura.nl' class=''>Mojura</a>",
               UBBParser.parse("[url=http://www.mojura.nl]Mojura[/url]"))
               
  assert_equal("<a href='mailto:info@mojura.nl' class=''>info@mojura.nl</a>",
               UBBParser.parse("[email]info@mojura.nl[/email]", {:protect_email => false}))
               
  assert_equal("<a href='mailto:info@mojura.nl' class=''>info@mojura.nl</a>",
               UBBParser.parse("info@mojura.nl", {:protect_email => false}))
               
  assert_equal("<a href='mailto:info@mojura.nl' class=''>Mojura</a>",
               UBBParser.parse("[email=info@mojura.nl]Mojura[/email]", {:protect_email => false}))
               
  assert_equal("<span class='ubbparser-error'>UBB error: invalid email address info@1.n</span>",
               UBBParser.parse("[email=info@1.n]Mojura[/email]"))

  assert_equal("<iframe src='http://www.mojura.nl' class=''></iframe>",
               UBBParser.parse("[iframe]http://www.mojura.nl[/iframe]"))
               
  assert_equal("<iframe src='http://www.mojura.nl' class='myclass1 myclass2'></iframe>",
               UBBParser.parse("[iframe]http://www.mojura.nl[/iframe]", {:class_iframe => "myclass1 myclass2"}))
               
 end
 
end