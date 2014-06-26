#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;
use Data::Dumper;

use Test::More;
require Test::NoWarnings;

use MediaWords::Util::Config;

use_ok( 'MediaWords::Tagger::Calais' );

my $test_cases = [
    {
        test_name  => 'obama_1',
        test_input => <<'__END_TEST_CASE__',
WASHINGTON— Add this to Barack Obama's to-do list: Find a commerce secretary -- for a third time. Republican Sen. Judd Gregg of New Hampshire backed out on Thursday, citing "irresolvable conflicts" with the new Democratic president's policies. That was just one week after Obama tapped him for the post the president originally gave to New Mexico Gov. Bill Richardson. He withdrew after the disclosure that a grand jury is investigating allegations of wrongdoing in the awarding of contracts in his state. Now, it's anyone's guess who will fill the job -- or when. The search for a commerce secretary has never yielded a large number of prospective candidates. There were few names batted around before Richardson was announced as Obama's top choice last year. And, when he abandoned his bid in early January, there was little speculation about a replacement until Gregg's name surfaced -- a full month later. "The president asked me to do it," Gregg said of the job offer during a news conference. "I said yes. That was my mistake." Obama offered a somewhat different account. "It comes as something of a surprise, because the truth, you know, Mr. Gregg approached us with interest and seemed enthusiastic," Obama said in an interview with the Springfield (Ill.) Journal-Register. Later, he told reporters traveling with him on Air Force One that he was glad Gregg "searched his heart" and changed course now before the Senate confirmed him to the Cabinet post. "Clearly he was just having second thoughts about leaving the Senate, a place where he's thrived," Obama added. The unexpected withdrawal came just three weeks into Obama's presidency and on the heels of several other Cabinet troubles. The new president is expending political capital for his economic stimulus package while the country continues to face threats abroad. Now Obama also finds himself needing to fill two vacancies -- at Commerce and at the Health and Human Services Department. Former Senate Democratic leader Tom Daschle withdrew his nomination for that post amid a tax controversy. Treasury Secretary Tim Geithner was confirmed despite revelations that he had not paid some of his taxes on time. Gregg was one of three Republicans Obama had put in his Cabinet to emphasize his campaign pledge that he would be an agent of bipartisan change. White House Chief of Staff Rahm Emanuel said Gregg told the White House early this week that he was having second thoughts and met with Obama about them during an Oval Office meeting Wednesday. Emanuel said there were no hard feelings, and "it's better we figured this out now than later." "He went into this eyes open and he realized over time it wasn't going to be a good fit," Emanuel added. Gregg said he'd always been a strong fiscal conservative and added: "It really wasn't a good pick." In an interview with The Associated Press, Gregg said, "For 30 years, I've been my own person in charge of my own views, and I guess I hadn't really focused on the job of working for somebody else and carrying their views, and so this is basically where it came out." Gregg, 61, said he changed his mind after realizing he wasn't ready to "trim my sails" to be a part of Obama's team. "I just sensed that I was not going to be good at being anything other than myself," he said. The New Hampshire senator also said he would probably not run for a new term in 2010. In his statement, Gregg said his withdrawal had nothing to do with the vetting into his past that potential Cabinet officials must undergo. He told the AP he foresaw conflicts over health care, global warming and taxes. He also cited both the stimulus and the census as areas of disagreement with the administration. When the Senate voted on the president's massive stimulus plan earlier this week, Gregg did not vote. The bill passed with all Democratic votes and just three Republican votes. Asked by reporters whether the White House could have used his vote on the plan, Gregg said, "I'm sure that's true" and said the administration had asked him to vote for it. Conservatives in both houses have been relentless critics of the centerpiece of Obama's economic recovery plan, arguing it is filled with wasteful spending and won't create enough jobs. The Commerce Department has jurisdiction over the Census Bureau, and the administration recently took steps to assert greater control. The outcome of the census has deep political implications, since congressional districts are drawn on the basis of population. Obama must find commerce secretary -- again
__END_TEST_CASE__
        ,
        test_output =>
'air force one, barack obama, bill richardson, bureau of the census, democratic leader tom daschle withdrew, department of commerce, gregg said his withdrawal, he withdrew, health and human services department, illinois, judd gregg, new hampshire, post, rahm emanuel, senate, the associated press, the cabinet post, tim geithner, tom daschle, white house'
    },
    {
        test_name  => 'random',
        test_input => <<'__END_TEST_CASE__',
Jul 30 - Chemical company Ineos develops technology to make bioethanol from waste.                      With soaring oil prices and government policy drives to run car fleets on cleaner energy sources that emit fewer greenhouse gases, biofuels are growing in popularity. But with land being used to grow biofuel rather than food crops the shine has come off their green credentials. Chemicals company Ineos thinks it has cracked the fuel v food debate with new technology that produces bioethanol from waste.  Michelle Carlile-Alkhouri reports.     Thomson Reuters is the world's largest international multimedia news agency, providing investing news, world news, business news, technology news, headline news, small business news, news alerts, personal finance, stock market, and mutual funds information available on Reuters.com, video, mobile, and interactive television platforms. Thomson Reuters journalists are subject to an Editorial Handbook which requires fair presentation and disclosure of relevant interests.     NYSE and AMEX quotes delayed by at least 20 minutes. Nasdaq delayed by at least 15 minutes. For a complete list of exchanges and delays, please click here .
  ];
__END_TEST_CASE__
        ,
        test_output =>
'amex, biofuels, car fleets, chemicals, cleaner energy sources, food, food debate, ineos, michelle carlile-alkhouri, oil prices, personal finance, technology news, thomson reuters'
    }
];

sub main()
{
    my $key = MediaWords::Util::Config::get_config->{ mediawords }->{ calais_key };

    if ( !defined( $key ) )
    {
        say STDERR 'skipping calais tests because the calais key is not defined';
        done_testing();
        return;
    }

    foreach my $test_case ( @{ $test_cases } )
    {
        my $error_message;

        my $tag_result = MediaWords::Tagger::Calais::get_tags( $test_case->{ test_input } );

        isa_ok( $tag_result, 'HASH' );

        my $tags = $tag_result->{ tags };

        #print Dumper($tags);

        isa_ok( $tags, 'ARRAY' );

      SKIP:
        {
            skip "No tags array ", 1, unless $tags;

            is( join( ", ", map { $_ } @{ $tags } ), $test_case->{ test_output }, $test_case->{ test_name } );
        }
    }

    Test::NoWarnings::had_no_warnings();

    done_testing();
}

main();
