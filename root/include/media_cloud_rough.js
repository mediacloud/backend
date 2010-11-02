var visible = true; 
var wordcloud = true; //We start off showing the word cloud

function DisplayDIV(d) {  
	if (visible == false) { //if we're only viewing one data set right now
		document.getElementById(d).style.display = "block";
		 $('#compare').html("Use single Data Source");
		visible = true;
		$('#compare_media_sets').val("true");
	}
	else {  //if we're allready viewing both data sets
	    document.getElementById(d).style.display = "none";
	    $('#compare').html("Compare this Data Source");
		visible = false;
		//this is where you want to set all of Data Set #2's information to NULL again, just in case they filled anything in
		$('#compare_media_sets').val("false");
	}
}//end function
function swapDIV(s) {
	if (s == 'CMcontentarea') { //if we want to view the Coverage Map
		//turn on the appropriate content area
		document.getElementById('CMcontentarea').style.display = "block";
		document.getElementById('WCcontentarea').style.display = "none";
		//fix the styles of the tabs
		$('#coveragemap').toggleClass('contentSelected contentUnselected');
		$('#wordcloud').toggleClass('contentSelected contentUnselected');
	}
	else {  //we want to view the word cloud
		//turn on the appropriate content area
	    document.getElementById('WCcontentarea').style.display = "block";
		document.getElementById('CMcontentarea').style.display = "none";
		//fix the styles of the tabs
		$('#coveragemap').toggleClass('contentSelected contentUnselected');
		$('#wordcloud').toggleClass('contentSelected contentUnselected');
	}	
}//end function

	

//function HideDIV(d) { document.getElementById(d).style.display = "none"; ColorDIV(d + 'Select', '#edf2d5');}
//function ColorDIV(d, e) { document.getElementById(d).style.backgroundColor=e; }
