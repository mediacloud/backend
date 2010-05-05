function GetY( oElement )

{

    var iReturnValue = 0;

    while( oElement != null ) {

        iReturnValue += oElement.offsetTop;

        oElement = oElement.offsetParent;

    }

    return iReturnValue;

}



function GetX( oElement )

{

    var iReturnValue = 0;

    while( oElement != null ) {

        iReturnValue += oElement.offsetLeft;

        oElement = oElement.offsetParent;

    }

    return iReturnValue;

}



function GetWidth (oElement) 

{

    return oElement.offsetWidth;

}



function GetHeight(oElement) 

{

    return oElement.offsetHeight;

}
function block(e)

{

    var targ;

    if (!e)

    {

      var e=window.event;

    }

    if (e.target)

    {

      targ=e.target;

    }

    else if (e.srcElement)

    {

      targ=e.srcElement;

    }

    if (targ.nodeType==3) // defeat Safari bug

    {

      targ = targ.parentNode;

    }

    var tname;

    tname=targ.tagName;

    targ.style.backgroundColor = "red";



    //alert("You clicked on a " + tname + " element.");
    //
    //}
    //
    //
 }

function unblock(e)

{



    var targ;

    if (!e)

    {

      var e=window.event;

    }

    if (e.target)

    {

      targ=e.target;

    }

    else if (e.srcElement)

    {

      targ=e.srcElement;

    }

    if (targ.nodeType==3) // defeat Safari bug

    {

      targ = targ.parentNode;

     }

    var tname;

    tname=targ.tagName;

    targ.style.backgroundColor = "";

    //alert("You clicked on a " + tname + " element.");
    //
    //}
    //
}

function getInnerText(elt) {

	var _innerText = elt.innerText;

	if (_innerText == undefined) {

  		_innerText = elt.innerHTML.replace(/<[^>]+>/g,"");

	}

	return _innerText;

}



var nbNode = 0;



// Louvan

function retrieveElementInfo(e) 

{

 var targ;

    if (!e)

    {

      var e=window.event;

    }

    if (e.target)

    {

      targ=e.target;

    }

    else if (e.srcElement)

    {

      targ=e.srcElement;

    }

    if (targ.nodeType==3) 

    {

      targ = targ.parentNode;

    }

    var tname;

    var str = "saya";

    tname=targ.tagName;

    

    // Get all the text boxes from the web page

    var txtTagName = parent.document.getElementById("txtTagName");
    var txtHtml= parent.document.getElementById("txtInnerHtml");


    var txtInnerText = parent.document.getElementById("txtInnerText");

    var txtImgNum = parent.document.getElementById("txtImgNum");

    var txtInteractionNum = parent.document.getElementById("txtInteractionNum");

    var txtFormNum = parent.document.getElementById("txtFormNum");

    var txtOptionNum = parent.document.getElementById("txtOptionNum");

    var txtTableNum = parent.document.getElementById("txtTableNum");

    var txtDivNum = parent.document.getElementById("txtDivNum");

    var txtLinkNum = parent.document.getElementById("txtLinkNum");

    var txtParaNum = parent.document.getElementById("txtParaNum");

    var txtCenterX = parent.document.getElementById("txtCenterX");

    var txtCenterY = parent.document.getElementById("txtCenterY");

    var txtWidth = parent.document.getElementById("txtWidth");

    var txtHeight = parent.document.getElementById("txtHeight");

    var txtLinkToTextRatio = parent.document.getElementById("txtLinkToTextRatio");

    var txtInnerTextValue = parent.document.getElementById("txtInnerTextValue");

    var txtDOMHeight = parent.document.getElementById("txtDOMHeight");

    var txtHeaderAround = parent.document.getElementById("txtHeaderAround");

    var txtLinkLength = parent.document.getElementById("txtLinkLength");

    var txtStringLength = parent.document.getElementById("txtStringLength");

    var txtInnerTextAll = parent.document.getElementById("txtInnerTextAll");

    

    // Get all the necessary elements

    var imgNumTotal = document.getElementsByTagName("IMG").length;

    var inputNumTotal = document.getElementsByTagName("INPUT").length; 

    var selectNumTotal =  document.getElementsByTagName("SELECT").length;

   // var interactionNumTotal = 1;

    var interactionNumTotal = inputNumTotal + selectNumTotal;

    var formNumTotal = document.getElementsByTagName("FORM").length;

    var optionNumTotal = document.getElementsByTagName("OPTION").length;

    var tableNumTotal = document.getElementsByTagName("TABLE").length + document.getElementsByTagName("TD").length +document.getElementsByTagName("TR").length;

    var divNumTotal = document.getElementsByTagName("DIV").length;

    var paraNumTotal = document.getElementsByTagName("P").length;

    var linkNumTotal = document.getElementsByTagName("A").length;

    var links = document.getElementsByTagName("A");

    var textTotal = getInnerText(document.body).length;

    var innerText = getInnerText(targ).length;

    var innerHTMLTotal = document.body.innerHTML.length;

    var linkLength = calculateLinkLength(targ);

    var bodyElmt = document.getElementsByTagName("BODY");

    var DOMHeightTotal = getBlockHeight(bodyElmt[0],0);

    var body_element = document.getElementsByTagName("body").item(0);

		  

    maxStringLengthTemp = 0;

    traverseDomTree_recurse(body_element, 0);

    var globalStringTotal = globalString;

    

    maxStringLengthTemp = 0;

    traverseDomTree_recurse(targ);

    

    var globalStringLocal = globalString;

    

    txtTagName.value = tname;

    txtHtml.value = (innerHTMLTotal != 0)?(targ.innerHTML.length/innerHTMLTotal):0;

    txtInnerText.value = (textTotal != 0)?(innerText/textTotal):0;

    txtImgNum.value = (imgNumTotal!= 0)?getNbChildrenByName(targ,"IMG")/imgNumTotal:0;

    txtInteractionNum.value = (interactionNumTotal != 0)? ((getNbChildrenByName(targ, "INPUT") + getNbChildrenByName(targ, "SELECT"))/interactionNumTotal):0;

    txtFormNum.value = (formNumTotal != 0)? (getNbChildrenByName(targ, "FORM")/formNumTotal):0;

    txtOptionNum.value = (optionNumTotal != 0)? (getNbChildrenByName(targ, "OPTION")/optionNumTotal):0;

    txtTableNum.value = (tableNumTotal != 0)? ((getNbChildrenByName(targ, "TABLE") + getNbChildrenByName(targ, "TR") + getNbChildrenByName(targ, "TD"))/tableNumTotal):0;

    txtDivNum .value = (divNumTotal != 0)? (getNbChildrenByName(targ, "DIV")/divNumTotal) :0;

    txtLinkNum.value = (linkNumTotal!= 0)? (getNbChildrenByName(targ, "A")/linkNumTotal):0;

    txtParaNum.value = (paraNumTotal != 0)?(getNbChildrenByName(targ, "P")/paraNumTotal):0;

    txtCenterX.value = ((GetX(targ) + (targ.offsetWidth/2))/document.body.offsetWidth);

    txtCenterY.value = ((GetY(targ) + (targ.offsetHeight/2))/document.body.offsetHeight);

    txtWidth.value = targ.offsetWidth/document.body.offsetWidth;

    txtHeight.value = targ.offsetHeight/document.body.offsetHeight;

    txtLinkToTextRatio.value = (innerText != 0)?(linkLength/innerText):0;
    

    //txtInnerTextValue.value = getInnerText(targ);

    //txtDOMHeight.value = (DOMHeightTotal != 0)? (getBlockHeight(targ,0)/DOMHeightTotal) ;
    var DOMHeightLocal = getBlockHeight(targ,0);
    var DOMHeightNormalized = DOMHeightLocal/DOMHeightTotal;
    txtDOMHeight.value = (DOMHeightTotal != 0)? (DOMHeightNormalized) :0;

    txtHeaderAround.value  = isHeaderAround(targ);

    txtLinkLength.value = linkLength;

    txtStringLength.value = globalStringLocal.length/globalStringTotal.length;

   txtInnerTextAll.value = getInnerText(document.body);

    

    className ="";

    classId="";

    if (targ.className) {

        className = targ.className;

    }

    if (targ.classId) {

        

    }
	//alert(DOMHeightNormalized);

    //alert("Global: "+globalStringTotal+ "Local :"+globalStringLocal+" Ratio:"+globalStringLocal.length/globalStringTotal.length);

    //alert("Class name:"+targ.className+" Class id:"+targ.classId);

    /*alert("Nb Img Total :"+imgNumTotal+"\n"+

          "Nb Interaction Total :"+interactionNumTotal+"\n"+

          "Nb Form Total :"+formNumTotal+"\n"+

          "Nb Option Total :"+optionNumTotal+"\n"+

          "Nb Table Total :"+tableNumTotal+"\n"+

          "Nb DIV Total :"+divNumTotal+"\n"+

          "Nb Paragraph Total :"+paraNumTotal+"\n"+

          "Nb Link Total :"+linkNumTotal+"\n"+

          "Nb Text Total :"+textTotal+"\n"+

          "Link Length: "+linkLength+

          "Inner Text: "+innerText);*/

}



function traverseDOMTree(currentElement, depth, tagNameStr)

{

  var x = 0;

	

  if (currentElement)

  {

	  

    var j;

    var tagName=currentElement.tagName;

    

    var tagNameStrCopy = tagNameStr;

    // Prints the node tagName, such as <A>, <IMG>, etc

    if (tagName == tagNameStr) {

    	nbNode++;

    }

   



    // Traverse the tree

    var i=0;

    var currentElementChild=currentElement.childNodes[i];

    while (currentElementChild)

    {

      traverseDOMTree(currentElementChild, depth+1, tagNameStr);

      i++;

      currentElementChild=currentElement.childNodes[i];

    }

    // The remaining code is mostly for formatting the tree

  }

}



function getNbChildrenByName(domElement, tagNameStr )

{

 

  nbNode = 0;

  traverseDOMTree(domElement, 1, tagNameStr);

  return nbNode;

}



function calculateLinkLength(domElement) {

    textLinkLength = 0;

    traverseLinks(domElement,1);

    return textLinkLength;

}



function traverseLinks(currentElement, depth) {

 var x = 0;

	

  if (currentElement)

  {

	  

    var j;

    var tagName=currentElement.tagName;

    



    // Prints the node tagName, such as <A>, <IMG>, etc

    if  (tagName == "A" || tagName == "a") {

       

            textLinkLength = textLinkLength + getInnerText(currentElement).length;

       

    }



    // Traverse the tree

    var i=0;

    var currentElementChild=currentElement.childNodes[i];

    while (currentElementChild)

    {

      traverseLinks(currentElementChild, depth+1);

      i++;

      currentElementChild=currentElement.childNodes[i];

    }

    // The remaining code is mostly for formatting the tree

  }

   

}



function getBlockHeight(domElement, height) {

    var count = height;

    if (domElement.childNodes.length > 0) {

        var htemp = 0;

        var fortmp = count;

        

        var length = domElement.childNodes.length;

        var i = 0;

        while (i <  length) {

            currentElementChild = domElement.childNodes[i];

            if (isStructuralTag(currentElementChild)) {

                htemp = getBlockHeight(currentElementChild, count+1);

            }else {

                htemp = getBlockHeight(currentElementChild, count);

            }

            if (htemp > fortmp) {

                fortmp = htemp;

            }

        }

        if (fortmp > count) {

            count = fortmp;

        }

    }

    

    return count;

}



function isStructuralTag(domElmt) {

    var tagName = domElmt.tagName;

    tagName = tagName.toUpperCase();

    if (tagName == "UL" || tagName == "LI" || tagName == "DIV" || tagName == "TABLE" || tagName == "TR" || tagName == "TD" || tagName == "SPAN"  ) {

        return true;

    }else {

        return false;

    }

}





function getBlockHeight(domElement, height) {

    var count = height;

    //var 

    if (domElement.hasChildNodes()) {

        var htemp = 0;

        var fortmp = count;

        

        var length = domElement.childNodes.length;

        var i = 0;

        while (i <  length) {

            currentElementChild = domElement.childNodes[i];

            if (isStructuralTag(currentElementChild)) {

                htemp = getBlockHeight(currentElementChild, count+1);

            }else {

                htemp = getBlockHeight(currentElementChild, count);

            }

            if (htemp > fortmp) {

                fortmp = htemp;

            }

            i++;

        }

        if (fortmp > count) {

            count = fortmp;

        }

    }

    

    return count;

}



function isStructuralTag(domElmt) {

    var tagName = domElmt.nodeName;

    tagName = tagName.toUpperCase();

    if (tagName == "UL" || tagName == "LI" || tagName == "DIV" || tagName == "TABLE" || tagName == "TR" || tagName == "TD" || tagName == "SPAN"  ) {

        return true;

    }else {

        return false;

    }

} 



function isHeaderAround(domElement) {

   var selfName = domElement.nodeName;

	if (selfName == "H1" || selfName == "H2" || selfName == "H3" || selfName == "H4")

		return 1;

	// previous sibling

	var prev = domElement.previousSibling;

	while (prev) {

		var tagName = prev.nodeName;

		tagName = tagName.toUpperCase();

		if (tagName == "H1" || tagName == "H2" || tagName == "H3" || tagName == "H4" )

		return 1;

		prev = prev.previousSibling;

	}	

	

	var next = domElement.nextSibling;

	while (next) {

		var tagName = next.nodeName;

		tagName = tagName.toUpperCase();

		if (tagName == "H1" || tagName == "H2" || tagName == "H3" || tagName == "H4" )

		return 1;

		next = next.nextSibling;

	}	

	

	var parent = domElement.parentNode;

	if (parent) {

		if (tagName == "H1" || tagName == "H2" || tagName == "H3" || tagName == "H4" )

		return 1;

	}

	

	

	 var length = domElement.childNodes.length;

     var i = 0;

	 while (i <  length) {

	        currentElementChild = domElement.childNodes[i];

	        var tagName = currentElementChild.nodeName;

			tagName = tagName.toUpperCase();

	       if (tagName == "H1" || tagName == "H2" || tagName == "H3" || tagName == "H4" )

				return 1;

	        i++;

	    }

	

	return 0;

} 



function traverseDomTree(targ) {

		  var body_element = document.getElementsByTagName("body").item(0);

		  

		  maxStringLengthTemp = 0;

		  traverseDomTree_recurse(body_element, 0);

		  var globalStringTotal = globalString;

		  maxStringLengthTemp = 0;

		  traverseDomTree_recurse(targ);

		  var globalStringLocal = globalString;

		  //alert("The end "+globalStringTotal+ "Length: "+globalStringTotal.length+"\n"+globalStringLocal+" Length: "+globalStringLocal.length+"\n Ratio :"+globalStringLocal.length/globalStringTotal.length); 

}

var maxStringLengthTemp = 0;

var globalString ="";

/*var nbNode = 0;*/



String.prototype.trim = function () {

return this.replace(/^\s*/, "").replace(/\s*$/, "");

}



function traverseDomTree_recurse(curr_element, level) {

  var i;

  if(curr_element.childNodes.length <= 0) {

    // This is a leaf node.

    

    if(curr_element.nodeName == "#text") {

      // This is a text leaf node,

      // with the following text.

      

      var node_text = curr_element.data.trim();

      if (node_text.length > maxStringLengthTemp && curr_element.parentNode.tagName != "NOSCRIPT" && curr_element.parentNode.tagName != "IFRAME") {

     

	   	globalString = node_text;   

	   	maxStringLengthTemp = node_text.length;

      }

     }

  } else {

 // alert("Hai2");

    // Expand each of the children of this node.

    for(i=0; curr_element.childNodes.item(i); i++) {

      traverseDomTree_recurse(curr_element.childNodes.item(i), level+1);

    }

  }

  

}
</script>

