#!/usr/bin/env perl
#
# Test text similarity scoring
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Time::HiRes;
use MediaWords::Util::Text;

sub main
{
    my $text_description = <<EOF;
While Speaker John A. Boehner was harsh in his public criticism of conservative advocacy groups opposed to a new bipartisan budget deal, his attack on the organizations was even more pointed when he was behind closed doors.

“They are not fighting for conservative principles,” Mr. Boehner told rank-and-file House Republicans during a private meeting on Wednesday as he seethed and questioned the motives of the groups for piling on against the plan before it was even made public.
EOF

    my $text_body = <<EOF;
“They are not fighting for conservative policy,” he continued, according to accounts of those present. “They are fighting to expand their lists, raise more money and grow their organizations, and they are using you to do it. It’s ridiculous.”

Representatives of the activist groups dismissed that assertion and called the speaker’s denunciation a diversion tactic.

Still, Mr. Boehner’s tough talk in taking on interests considered vital to generating Republican voter enthusiasm and building fierce opposition to President Obama’s agenda appeared to represent a turning point in Republican coalition building in the aftermath of the government shutdown.

His break with the groups was magnified because it came after Senator Mitch McConnell of Kentucky, the Republican leader, had condemned a conservative group that has backed one of his opponents. And Mr. Boehner went on the offensive just as the executive director of the Republican Study Committee, the main organization for House conservatives, was dismissed, adding to the appearance that ties between the activist right and elected Republicans were unraveling.

Republican congressional leaders blame advocacy groups like Heritage Action for America and the Senate Conservatives Fund for the shutdown — for goading House and Senate Republicans into a dead-end insistence on financing the government only if the new health law was overturned. The predictable impasse over that demand and the eventual Republican capitulation damaged the standing of Republicans as well as Congress.

“The shutdown was the first time a group largely drove the Republican Party in the Senate towards something that was disadvantageous,” said one top Republican Senate official.

In addition, some congressional leaders are no longer willing to remain silent to avoid antagonizing important political partners. They have seen a clear downside to the rising influence of outside conservative organizations that promote divisive primary fights, producing flawed candidates who lose winnable seats to Democrats.

The 2014 election cycle probably represents Mr. McConnell’s last chance to regain the title of majority leader, and he seems determined not to let conservative activists spoil his chances. His actions and comments both publicly and privately since the shutdown have shown that he does not intend to brook much interference from conservative activists.

Just as important, Mr. McConnell does not want to regain the majority only to find himself surrounded by conservative firebrands like Representative Steve Stockman of Texas, who is now challenging Senator John Cornyn, the No. 2 Senate Republican. Mr. Boehner has proved that presiding over an ungovernable majority is not an enviable job.

Seeming to relish his new liberation, Mr. Boehner on Thursday skewered the organizations for a second straight day, just a few hours before the House overwhelmingly approved the budget plan at the center of the dispute with the support of 169 Republicans. Sixty-two opposed it.

“They’re pushing our members in places where they don’t want to be,” Mr. Boehner said. “And frankly, I just think that they’ve lost all credibility.”

Conservative leaders said they viewed Mr. Boehner’s attacks as tantamount to a declaration of war and accused him of trying to change the subject from a budget plan that increases spending and sacrifices earlier hard-won fiscal victories by House Republicans.
EOF

    my $time_before = Time::HiRes::time();
    my $score       = MediaWords::Util::Text::get_similarity_score( $text_description, $text_body, 'en' );
    my $time_after  = Time::HiRes::time();

    # Text::Similarity::Overlaps:
    #   Similarity score: 0.165837479270315
    #   Time: 0.020255

    print "Similarity score: $score\n";
    printf "Time: %2.6f\n", ( $time_after - $time_before );
}

main();
