/**
 * @author Stephane Roucheray 
 * @extends jquery
 */

jQuery.fn.iframeResize = function(options){
	var settings = jQuery.extend({
		width: "fill",
		height: "auto",
		autoUpdate : true
	}, options);
	var filler = 30;
	
	function onEachIframe(){
		var frame = jQuery(this);
		var body = frame.contents().find("body");
		
		frame.css("overflow", "hidden");
		if (settings.autoUpdate) {
			if (jQuery.browser.msie) {
				frame.attr("scrolling", "auto");
				setInterval(immediateResize, 1000);
			}
			else {
				body.bind("DOMSubtreeModified", {
					frame: frame
				}, resizeIframe);
			}
		}
		immediateResize();
		
		function immediateResize(){
			var e = jQuery.Event();
			e.data = {};
			e.data.frame = frame;
			resizeIframe.call(body, e);
		}
	}
	
	function resizeIframe(event){
		var body = jQuery(this);
		event.data.frame.css("width",  settings.width  == "fill" ? "100%" : parseInt(settings.height));
		event.data.frame.css("height", settings.height == "auto" ? body.outerHeight(true) + filler : parseInt(settings.height));
	}
	
	jQuery(this).children("iframe").each(onEachIframe);
};
