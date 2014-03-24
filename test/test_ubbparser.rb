$:.unshift File.join(File.dirname(__FILE__), '..')

require 'lib/ubbparser'
require 'test/unit'

# The UBBParserTester is the unit test for the UBB Parser.
class UBBParserTester < Test::Unit::TestCase

	def converting(url)
		url.gsub(/(\d+)/, "files/\\1")
	end

	def test_parse
		UBBParser.set_file_url_convert_method(method(:converting))

		assert_equal('This is a <strong>test</strong>',
		             UBBParser.parse('This is a [b]test[/b]'))

		assert_equal('<strong>test</strong>',
		             UBBParser.parse('[b]test[/b]'))

		assert_equal('This is a <strong><em>test</em></strong>',
		             UBBParser.parse('This is a [b][i]test[/i][/b]'))

		assert_equal('This is a <strong><em>test</em></strong>[/i]',
		             UBBParser.parse('This is a [b][i]test[/b][/i]'))

		assert_equal('just [something] unknown',
		             UBBParser.parse('just [something] unknown'))

		assert_equal("<a href='http://www.mojura.nl' class='ubb-url' target='_blank'>http://www.mojura.nl</a>",
		             UBBParser.parse('[url]http://www.mojura.nl[/url]'))

		assert_equal("<a href='http://www.mojura.nl' class='ubb-url' target='_blank'>http://www.mojura.nl</a>",
		             UBBParser.parse('http://www.mojura.nl'))

		assert_equal("<a href='http://www.mojura.nl' class='ubb-url' target='_blank'>Mojura</a>",
		             UBBParser.parse('[url=http://www.mojura.nl]Mojura[/url]'))

		assert_equal("<a href='mailto:info@mojura.nl' class='ubb-email'>info@mojura.nl</a>",
		             UBBParser.parse('[email]info@mojura.nl[/email]', {:protect_email => false}))

		assert_equal("<a href='mailto:info@mojura.nl' class='ubb-email'>info@mojura.nl</a>",
		             UBBParser.parse('info@mojura.nl', {:protect_email => false}))

		#assert_equal("<a href='mailto:info@mojura.nl' class='ubb-email'>info@mojura.nl</a>",
		#             UBBParser.parse("info@mojura.nl", {:protect_email => true}))

		assert_equal("<a href='files/12345' class='ubb-url'>12345</a>",
		             UBBParser.parse('[url]12345[/url]'))

		assert_equal("<a href='files/12345' class='ubb-url'>Testing</a>",
		             UBBParser.parse('[url=12345]Testing[/url]'))

		assert_equal("<a href='mailto:info@mojura.nl' class='ubb-email'>Mojura</a>",
		             UBBParser.parse('[email=info@mojura.nl]Mojura[/email]', {:protect_email => false}))

		assert_equal("<span class='ubb-email ubbparser-error'>UBB error: invalid email address info@1.n</span>",
		             UBBParser.parse('[email=info@1.n]Mojura[/email]'))

		assert_equal("<iframe src='http://www.mojura.nl' class='ubb-iframe'></iframe>",
		             UBBParser.parse('[iframe]http://www.mojura.nl[/iframe]'))

		assert_equal("<iframe src='http://www.mojura.nl' class='myclass1 myclass2'></iframe>",
		             UBBParser.parse('[iframe]http://www.mojura.nl[/iframe]', {:class_iframe => 'myclass1 myclass2'}))

		assert_equal("<table class='ubb-table'><tr><td>Test 1</td><td>Test 2</td></tr></table>",
		             UBBParser.parse('[table][tr][td]Test 1[/td][td]Test 2[/td][/tr][/table]'))

		assert_equal("<table class='ubb-table'><tr><td>Test 1</td><td>Test 2</td></tr></table>",
		             UBBParser.parse("[table]\n\n[tr]\n[td]Test 1[/td][td]Test 2[/td]\n[/tr]\n\n[/table]"))

		assert_equal('All html tags like &lt;b&gt;&lt;/b&gt;, &lt;i&gt;&lt;/i&gt; and &lt;script&gt;&lt;/script&gt; should be escaped.',
		             UBBParser.parse('All html tags like <b></b>, <i></i> and <script></script> should be escaped.'))

		assert_equal('All html tags like <strong>&lt;i&gt;&lt;/i&gt;</strong>, <strong>&lt;i&gt;&lt;/i&gt;</strong> and <strong>&lt;script&gt;&lt;/script&gt;</strong> should be escaped.',
		             UBBParser.parse('All html tags like [b]<i></i>[/b], [b]<i></i>[/b] and [b]<script></script>[/b] should be escaped.'))

		assert_equal("<table class='ubb-csv ubb-table'><tbody><tr><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></tbody></table>",
		             UBBParser.parse("[csv]\n1,2\n3,4[/csv]"))

		assert_equal("<table class='ubb-csv ubb-table'><tbody><tr><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></tbody></table>",
		             UBBParser.parse("[csv sepchar=;]\n1;2\n3;4[/csv]"))

		assert_equal("<h1>Header</h1>Body text",
		             UBBParser.parse("[h1]Header[/h1]\nBody text"))

		assert_equal("<h1>Test</h1>", UBBParser.parse("[h1]Test[/h1]"))
		assert_equal("<h2>Test</h2>", UBBParser.parse("[h2]Test[/h2]"))
		assert_equal("<h3>Test</h3>", UBBParser.parse("[h3]Test[/h3]"))
		assert_equal("<h4>Test</h4>", UBBParser.parse("[h4]Test[/h4]"))
		assert_equal("<h5>Test</h5>", UBBParser.parse("[h5]Test[/h5]"))
		assert_equal("<h6>Test</h6>", UBBParser.parse("[h6]Test[/h6]"))

		assert_equal("<div class='my-class'>Test</div>", UBBParser.parse("[class=my-class]Test[/class]"))
		assert_equal("<div class='my-class1 my-class2'>Test</div>", UBBParser.parse("[class=my-class1 my-class2]Test[/class]"))

		assert_equal("<div style='color: white; margin: 0'>Test</div>", UBBParser.parse("[style=color: white; margin: 0]Test[/style]"))

		assert_equal("<h1>Test</h1>Test", UBBParser.parse("[h1]Test[/h1]\nTest"))
		assert_equal("<strong>Test</strong><br />Test", UBBParser.parse("[b]Test[/b]\nTest"))

		assert_equal("<a href='http://www.mojura.nl' class='ubb-url' target='_blank'>http://www.mojura.nl</a> is an example",
		             UBBParser.parse('http://www.mojura.nl is an example'))
	end

	def test_strip_tags
		assert_equal('This is a test',
		             UBBParser.strip_ubb('This is a [b][i]test[/i][/b]'))
	end

end