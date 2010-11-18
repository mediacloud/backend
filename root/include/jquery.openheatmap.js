/**
 * This script provides the interface to the OpenHeatMap rendering component
 *
 * To use it, call $('#yourelement').insertOpenHeatMap({ width: 800, height:400}) to add the
 * component to your page, and then wait for your onMapCreated() function to be called.
 * You can then call getOpenHeatMap() to grab the API object to continue construction
 *
 * The canonical source for this file is http://static.openheatmap.com/scripts/jquery.openheatmap.js
 
 Copyright (C) 2010 Pete Warden <pete@mailana.com>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

 **/

g_openHeatMapObjects = {};
g_openHeatMapUserData = {};

(function($) {
 
    $.fn.insertOpenHeatMap = function(settings) {
        var defaults = {
            mapName: 'openheatmap',
            width: 800,
            height: 600,
            prefer: 'flash',
            wmode: 'opaque',
            userData: null
        };

        if (document.location.protocol == 'https:')
            defaults['source'] = 'https://s3.amazonaws.com/static.openheatmap.com/openheatmap.swf';
        else
            defaults['source'] = 'http://static.openheatmap.com.s3.amazonaws.com/openheatmap.swf';
 
        if (settings) 
            settings = $.extend(defaults, settings);
        else
            settings = defaults;
 
        g_openHeatMapUserData[settings.mapName] = settings.userData;
 
        // See http://diveintohtml5.org/detect.html#canvas
        var hasCanvas = !!document.createElement('canvas').getContext;

        var hasFlash = jQuery.fn.flash.hasFlash(9,0,0);
 
        if (hasCanvas&&((settings.prefer==='canvas')||(!hasFlash)))
        {     
            this.each(function() {

                $(this).empty();

                var canvas = $(
                    '<canvas '
                    +'width="'+settings.width+'" '
                    +'height="'+settings.height+'"'
                    +'id="'+settings.mapName+'_canvas"'
                    +'"></canvas>'
                );

                var openHeatMap = new OpenHeatMap(canvas, settings.width, settings.height);
                
                g_openHeatMapObjects[settings.mapName] = openHeatMap;

                $(this).append(canvas);
                
                onMapCreated(settings.mapName);
            });
        }
        else
        {
            this.each(function() {
                var params = {};
                params.src = settings.source;
                params.src += '?mapname='+encodeURIComponent(settings.mapName);
                params.src += '&width='+settings.width;
                params.src += '&height='+settings.height;
                
                params.id = settings.mapName;
                params.name = settings.mapName;
                params.allowScriptAccess = "always";
                params.menu = false;
                if (settings.wmode!=='')
                    params.wmode = settings.wmode;

                $(this).empty();
                var widthString = settings.width+'px';
                var heightString = settings.height+'px';
                
                $(this).width(widthString);
                $(this).height(heightString);
                
                params.width = widthString;
                params.height = heightString;

                $(this).flash(params);

                // Dead-chicken-waving voodoo that I inserted whilst trying to get IE let
                // me call Flash from Javascript. It's probably no longer needed, but the
                // testing process to confirm that is too painful to contemplate right now
                window[settings.mapName] = document.getElementById(settings.mapName);
                document.getElementById(settings.mapName).setAttribute('classid','clsid:d27cdb6e-ae6d-11cf-96b8-444553540000');
            });        
        }
 
        return this;
    };
    
    $.getOpenHeatMap = function(mapName) {
        if (!mapName)
            mapName = 'openheatmap';
            
        if (typeof g_openHeatMapObjects[mapName] !== 'undefined')
        {
            return g_openHeatMapObjects[mapName];
        }
        else
        {
            var isIE = navigator.appName.indexOf("Microsoft") != -1;
            return (isIE) ? document.getElementsByName(mapName)[0] : document.getElementById(mapName);
        }
    };

    $.getOpenHeatMapUserData = function(mapName) {
        if (!mapName)
            mapName = 'openheatmap';

        return g_openHeatMapUserData[mapName];
    };
 
})(jQuery);

//-----------------------------------------------------------------------

/**
 * Flash (http://jquery.lukelutman.com/plugins/flash)
 * A jQuery plugin for embedding Flash movies.
 * 
 * Version 1.0
 * November 9th, 2006
 *
 * Copyright (c) 2006 Luke Lutman (http://www.lukelutman.com)
 * Dual licensed under the MIT and GPL licenses.
 * http://www.opensource.org/licenses/mit-license.php
 * http://www.opensource.org/licenses/gpl-license.php
 * 
 * Inspired by:
 * SWFObject (http://blog.deconcept.com/swfobject/)
 * UFO (http://www.bobbyvandersluis.com/ufo/)
 * sIFR (http://www.mikeindustries.com/sifr/)
 * 
 * IMPORTANT: 
 * The packed version of jQuery breaks ActiveX control
 * activation in Internet Explorer. Use JSMin to minifiy
 * jQuery (see: http://jquery.lukelutman.com/plugins/flash#activex).
 *
 **/ 
;(function(){
	
var $$;

/**
 * 
 * @desc Replace matching elements with a flash movie.
 * @author Luke Lutman
 * @version 1.0.1
 *
 * @name flash
 * @param Hash htmlOptions Options for the embed/object tag.
 * @param Hash pluginOptions Options for detecting/updating the Flash plugin (optional).
 * @param Function replace Custom block called for each matched element if flash is installed (optional).
 * @param Function update Custom block called for each matched if flash isn't installed (optional).
 * @type jQuery
 *
 * @cat plugins/flash
 * 
 * @example $('#hello').flash({ src: 'hello.swf' });
 * @desc Embed a Flash movie.
 *
 * @example $('#hello').flash({ src: 'hello.swf' }, { version: 8 });
 * @desc Embed a Flash 8 movie.
 *
 * @example $('#hello').flash({ src: 'hello.swf' }, { expressInstall: true });
 * @desc Embed a Flash movie using Express Install if flash isn't installed.
 *
 * @example $('#hello').flash({ src: 'hello.swf' }, { update: false });
 * @desc Embed a Flash movie, don't show an update message if Flash isn't installed.
 *
**/
$$ = jQuery.fn.flash = function(htmlOptions, pluginOptions, replace, update) {
	
	// Set the default block.
	var block = replace || $$.replace;
	
	// Merge the default and passed plugin options.
	pluginOptions = $$.copy($$.pluginOptions, pluginOptions);
	
	// Detect Flash.
	if(!$$.hasFlash(pluginOptions.version)) {
		// Use Express Install (if specified and Flash plugin 6,0,65 or higher is installed).
		if(pluginOptions.expressInstall && $$.hasFlash(6,0,65)) {
			// Add the necessary flashvars (merged later).
			var expressInstallOptions = {
				flashvars: {  	
					MMredirectURL: location,
					MMplayerType: 'PlugIn',
					MMdoctitle: jQuery('title').text() 
				}					
			};
		// Ask the user to update (if specified).
		} else if (pluginOptions.update) {
			// Change the block to insert the update message instead of the flash movie.
			block = update || $$.update;
		// Fail
		} else {
			// The required version of flash isn't installed.
			// Express Install is turned off, or flash 6,0,65 isn't installed.
			// Update is turned off.
			// Return without doing anything.
			return this;
		}
	}
	
	// Merge the default, express install and passed html options.
	htmlOptions = $$.copy($$.htmlOptions, expressInstallOptions, htmlOptions);
	
	// Invoke $block (with a copy of the merged html options) for each element.
	return this.each(function(){
		block.call(this, $$.copy(htmlOptions));
	});
	
};
/**
 *
 * @name flash.copy
 * @desc Copy an arbitrary number of objects into a new object.
 * @type Object
 * 
 * @example $$.copy({ foo: 1 }, { bar: 2 });
 * @result { foo: 1, bar: 2 };
 *
**/
$$.copy = function() {
	var options = {}, flashvars = {};
	for(var i = 0; i < arguments.length; i++) {
		var arg = arguments[i];
		if(arg == undefined) continue;
		jQuery.extend(options, arg);
		// don't clobber one flash vars object with another
		// merge them instead
		if(arg.flashvars == undefined) continue;
		jQuery.extend(flashvars, arg.flashvars);
	}
	options.flashvars = flashvars;
	return options;
};
/*
 * @name flash.hasFlash
 * @desc Check if a specific version of the Flash plugin is installed
 * @type Boolean
 *
**/
$$.hasFlash = function() {
	// look for a flag in the query string to bypass flash detection
	if(/hasFlash\=true/.test(location)) return true;
	if(/hasFlash\=false/.test(location)) return false;
	var pv = $$.hasFlash.playerVersion().match(/\d+/g);
	var rv = String([arguments[0], arguments[1], arguments[2]]).match(/\d+/g) || String($$.pluginOptions.version).match(/\d+/g);
	for(var i = 0; i < 3; i++) {
		pv[i] = parseInt(pv[i] || 0);
		rv[i] = parseInt(rv[i] || 0);
		// player is less than required
		if(pv[i] < rv[i]) return false;
		// player is greater than required
		if(pv[i] > rv[i]) return true;
	}
	// major version, minor version and revision match exactly
	return true;
};
/**
 *
 * @name flash.hasFlash.playerVersion
 * @desc Get the version of the installed Flash plugin.
 * @type String
 *
**/
$$.hasFlash.playerVersion = function() {
	// ie
	try {
		try {
			// avoid fp6 minor version lookup issues
			// see: http://blog.deconcept.com/2006/01/11/getvariable-setvariable-crash-internet-explorer-flash-6/
			var axo = new ActiveXObject('ShockwaveFlash.ShockwaveFlash.6');
			try { axo.AllowScriptAccess = 'always';	} 
			catch(e) { return '6,0,0'; }				
		} catch(e) {}
		return new ActiveXObject('ShockwaveFlash.ShockwaveFlash').GetVariable('$version').replace(/\D+/g, ',').match(/^,?(.+),?$/)[1];
	// other browsers
	} catch(e) {
		try {
			if(navigator.mimeTypes["application/x-shockwave-flash"].enabledPlugin){
				return (navigator.plugins["Shockwave Flash 2.0"] || navigator.plugins["Shockwave Flash"]).description.replace(/\D+/g, ",").match(/^,?(.+),?$/)[1];
			}
		} catch(e) {}		
	}
	return '0,0,0';
};
/**
 *
 * @name flash.htmlOptions
 * @desc The default set of options for the object or embed tag.
 *
**/
$$.htmlOptions = {
	height: 240,
	flashvars: {},
	pluginspage: 'http://www.adobe.com/go/getflashplayer',
	src: '#',
	type: 'application/x-shockwave-flash',
	width: 320		
};
/**
 *
 * @name flash.pluginOptions
 * @desc The default set of options for checking/updating the flash Plugin.
 *
**/
$$.pluginOptions = {
	expressInstall: false,
	update: true,
	version: '6.0.65'
};
/**
 *
 * @name flash.replace
 * @desc The default method for replacing an element with a Flash movie.
 *
**/
$$.replace = function(htmlOptions) {
// There's a bug with IE where if you add the flash object using the standard
// jQuery prepend/append method it appears but you can't call methods on it.
// To work around that problem I'm setting innerHTML in all cases, which
// seems to work across all my tested browsers.

//	this.innerHTML = '<div class="alt">'+this.innerHTML+'</div>';
//	jQuery(this)
//		.addClass('flash-replaced')
//		.prepend($$.transform(htmlOptions));
    this.innerHTML = $$.transform(htmlOptions);
};
/**
 *
 * @name flash.update
 * @desc The default method for replacing an element with an update message.
 *
**/
$$.update = function(htmlOptions) {
	var url = String(location).split('?');
	url.splice(1,0,'?hasFlash=true&');
	url = url.join('');
	var msg = '<p>This content requires the Flash Player. <a href="http://www.adobe.com/go/getflashplayer">Download Flash Player</a>. Already have Flash Player? <a href="'+url+'">Click here.</a></p>';
	this.innerHTML = '<span class="alt">'+this.innerHTML+'</span>';
	jQuery(this)
		.addClass('flash-update')
		.prepend(msg);
};
/**
 *
 * @desc Convert a hash of html options to a string of attributes, using Function.apply(). 
 * @example toAttributeString.apply(htmlOptions)
 * @result foo="bar" foo="bar"
 *
**/
function toAttributeString() {
	var s = '';
	for(var key in this)
		if(typeof this[key] != 'function')
			s += key+'="'+this[key]+'" ';
	return s;		
};
/**
 *
 * @desc Convert a hash of flashvars to a url-encoded string, using Function.apply(). 
 * @example toFlashvarsString.apply(flashvarsObject)
 * @result foo=bar&foo=bar
 *
**/
function toFlashvarsString() {
	var s = '';
	for(var key in this)
		if(typeof this[key] != 'function')
			s += key+'='+encodeURIComponent(this[key])+'&';
	return s.replace(/&$/, '');		
};
/**
 *
 * @name flash.transform
 * @desc Transform a set of html options into an embed tag.
 * @type String 
 *
 * @example $$.transform(htmlOptions)
 * @result <embed src="foo.swf" ... />
 *
 * Note: The embed tag is NOT standards-compliant, but it 
 * works in all current browsers. flash.transform can be
 * overwritten with a custom function to generate more 
 * standards-compliant markup.
 *
**/
$$.transform = function(htmlOptions) {
    argumentList = [];
    for (var key in htmlOptions)
    {
        var value = htmlOptions[key];
        argumentList.push(key);
        argumentList.push(value);
    }

    var attributes = getAttributesFromArguments(
        argumentList, 
        ".swf", 
        "movie", 
        "clsid:d27cdb6e-ae6d-11cf-96b8-444553540000", 
        "application/x-shockwave-flash"
    );

    var isIE  = (navigator.appVersion.indexOf("MSIE") != -1) ? true : false;
    var isWin = (navigator.appVersion.toLowerCase().indexOf("win") != -1) ? true : false;
    var isOpera = (navigator.userAgent.indexOf("Opera") != -1) ? true : false;

    var result = '';
    if (isIE && isWin && !isOpera)
    {
  		result += '<object ';
  		for (var i in attributes.objAttrs)
  			result += i + '="' + attributes.objAttrs[i] + '" ';
  		result += '>';
  		for (var i in attributes.params)
  			result += '<param name="' + i + '" value="' + attributes.params[i] + '" /> ';
  		result += '</object>';
    } else {
  		result += '<embed ';
  		for (var i in attributes.embedAttrs)
  			result += i + '="' + attributes.embedAttrs[i] + '" ';
  		result += '> </embed>';
    }
    
    return result;
};

function getAttributesFromArguments(args, ext, srcParamName, classid, mimeType){
  var ret = new Object();
  ret.embedAttrs = new Object();
  ret.params = new Object();
  ret.objAttrs = new Object();
  for (var i=0; i < args.length; i=i+2){
    var currArg = args[i].toLowerCase();    

    switch (currArg){	
      case "classid":
        break;
      case "pluginspage":
        ret.embedAttrs[args[i]] = args[i+1];
        break;
      case "src":
      case "movie":	
        args[i+1] = AC_AddExtension(args[i+1], ext);
        ret.embedAttrs["src"] = args[i+1];
        ret.params[srcParamName] = args[i+1];
        break;
      case "onafterupdate":
      case "onbeforeupdate":
      case "onblur":
      case "oncellchange":
      case "onclick":
      case "ondblClick":
      case "ondrag":
      case "ondragend":
      case "ondragenter":
      case "ondragleave":
      case "ondragover":
      case "ondrop":
      case "onfinish":
      case "onfocus":
      case "onhelp":
      case "onmousedown":
      case "onmouseup":
      case "onmouseover":
      case "onmousemove":
      case "onmouseout":
      case "onkeypress":
      case "onkeydown":
      case "onkeyup":
      case "onload":
      case "onlosecapture":
      case "onpropertychange":
      case "onreadystatechange":
      case "onrowsdelete":
      case "onrowenter":
      case "onrowexit":
      case "onrowsinserted":
      case "onstart":
      case "onscroll":
      case "onbeforeeditfocus":
      case "onactivate":
      case "onbeforedeactivate":
      case "ondeactivate":
      case "type":
      case "codebase":
        ret.objAttrs[args[i]] = args[i+1];
        break;
      case "id":
      case "width":
      case "height":
      case "align":
      case "vspace": 
      case "hspace":
      case "class":
      case "title":
      case "accesskey":
      case "name":
      case "tabindex":
        ret.embedAttrs[args[i]] = ret.objAttrs[args[i]] = args[i+1];
        break;
      default:
        ret.embedAttrs[args[i]] = ret.params[args[i]] = args[i+1];
    }
  }
  ret.objAttrs["classid"] = classid;
  if (mimeType) ret.embedAttrs["type"] = mimeType;
  return ret;
}

function AC_AddExtension(src, ext)
{
  var qIndex = src.indexOf('?');
  if ( qIndex != -1)
  {
    // Add the extention (if needed) before the query params
    var path = src.substring(0, qIndex);
    if (path.length >= ext.length && path.lastIndexOf(ext) == (path.length - ext.length))
      return src;
    else
      return src.replace(/\?/, ext+'?'); 
  }
  else
  {
    // Add the extension (if needed) to the end of the URL
    if (src.length >= ext.length && src.lastIndexOf(ext) == (src.length - ext.length))
      return src;  // Already have extension
    else
      return src + ext;
  }
}

/**
 *
 * Flash Player 9 Fix (http://blog.deconcept.com/2006/07/28/swfobject-143-released/)
 *
**/
if (window.attachEvent) {
	window.attachEvent("onbeforeunload", function(){
		__flash_unloadHandler = function() {};
		__flash_savedUnloadHandler = function() {};
	});
}
	
})();

function OpenHeatMap(canvas, width, height)
{
    this.__constructor = function(canvas, width, height)
    {
        this.initializeMembers();
        
        if ((navigator.userAgent.indexOf('iPhone') != -1) || 
            (navigator.userAgent.indexOf('iPod') != -1))
        {
            this._settings.point_blob_tile_size = 32;
        }

        this.setSize(width, height);

        this.createViewerElements();

        this.setLatLonViewingArea(80, -180, -75, 180);

        this._canvas = canvas;

        this._canvas
        .bind('click', this, this.mapMouseClickHandler)
        .bind('dblclick', this, this.mapMouseDoubleClickHandler)
        .bind('mousedown', this, this.mapMouseDownHandler)
        .bind('mousemove', this, this.mapMouseMoveHandler)
        .bind('mouseout', this, this.mapMouseOutHandler)
        .bind('mouseover', this, this.mapMouseOverHandler)
        .bind('mouseup', this, this.mapMouseUpHandler);

        _dirty = true;

        var instance = this;

        window.setInterval(function() { instance.doEveryFrame(); }, 30);
    };
    
    this.initializeMembers = function() {
    
        this._mainCanvas = null;
        this._dirty = true;
        this._redrawCountdown = 0;

        this._wayDefaults = {
            color: 0x000000,
            alpha: 1.0,
            line_thickness: 0,
            line_color: 0x000000,
            line_alpha: 0.0
        };

        this._colorGradient = [
            {alpha: 0x00, red: 0x00, green: 0xb0, blue: 0x00},
            {alpha: 0x7f, red: 0xe0, green: 0xe0, blue: 0x00},
            {alpha: 0xff, red: 0xff, green: 0x00, blue: 0x00},
        ];

        this._onClickFunction = null;
        this._onDoubleClickFunction = null;
        this._onMouseDownFunction = null;
        this._onMouseUpFunction = null;
        this._onMouseOverFunction = null;
        this._onMouseOutFunction = null;
        this._onMouseMoveFunction = null;
        this._onFrameRenderFunction = null;
        this._onDataChangeFunction = null;
        this._onWaysLoadFunction = null;
        this._onValuesLoadFunction = null;
        this._onErrorFunction = null;
        this._onViewChangeFunction = null;

        this._nodes = {};
        this._ways = {};

        this._waysLoader;
        this._waysFileName = "";

        this._valuesLoader;
        this._valuesFileName = "";

        this._valueHeaders = null;
        this._valueData = null;
        this._timeColumnIndex;
        this._valueColumnIndex;

        this._smallestValue;
        this._largestValue;

        this._hasTime = false;
        this._frameTimes = [];
        this._frameIndex = 0;

        this._tagMap = {};

        this._latLonToXYMatrix = new Matrix();
        this._xYToLatLonMatrix = new Matrix();

        this._worldBoundingBox = new Rectangle();
        this._waysGrid = null;

        this._inlays = [];

        this._valuesDirty = false;

        this._mainBitmapTopLeftLatLon = null;
        this._mainBitmapBottomRightLatLon = null;

        this._isDragging = false;
        this._lastDragPosition = null;
        this._lastClickTime = 0;

        this._zoomSlider = null;

        this._foundTimes = {};

        this._hasBitmapBackground = false;

        this._hasPointValues = false;
        this._latitudeColumnIndex = -1;
        this._longitudeColumnIndex = -1;

        this._pointsGrid = null;

        this._mapTiles = {};

        this._settings = {
            width: 800,
            height: 600,
            zoom_slider_power: 5.0,
            zoomed_out_degrees_per_pixel: -180,
            zoomed_in_degrees_per_pixel: -0.01,
            is_gradient_value_range_set: false,
            gradient_value_min: 0,
            gradient_value_max: 0,
            point_blob_radius: 1.0,
            point_blob_value: 1.0,
            credit_text: 'OpenHeatMap',
            credit_color: '0x303030',
            title_text: '',
            title_size: 15,
            title_color: '0x000000',
            title_background_color: '0xd0e0ff',
            title_background_alpha: 1.0,
            time_range_start: null,
            time_range_end: null,
            force_outlines: false,
            show_map_tiles: false,
            map_server_root: 'http://a.tile.openstreetmap.org/',
            map_tile_width: 256,
            map_tile_height: 256,
            map_tile_origin_lat: 85.05112877980659,
            map_tile_origin_lon: -180,
            map_tile_match_factor: 1.2,
            world_lat_height: -170.102258,
            world_lon_width: 360,
            inlay_border_color: 0x000000,
            ocean_color: 0xd0e0ff,
            information_alpha: 1.0,
            is_point_blob_radius_in_pixels: false,
            point_bitmap_scale: 2,
            tab_height: 15,
            clear_ways: true,
            is_value_distance: false,
            point_blob_tile_size: 128,
            show_tabs: true,
            show_zoom: true,
            allow_pan: true,
            point_drawing_shape: 'blob',
            circle_line_color: 0x000000,
            circle_line_alpha: 1.0,
            circle_line_thickness: 1.0,
            max_fps: 2.0,
            circle_minimum_radius: 2.0
        };

        this._lastSetWayIds = {};

        this._credit = null;
        this._title = null;

        this._popups = [];

        this._informationLayerCanvas = null;

        this._mapTilesDirty = false;
	
        this._tabColumnIndex = -1;
        this._hasTabs = false;
        this._tabNames = [];
        this._tabInfo = {};
        this._selectedTabIndex = 0;
        this._hoveredTabIndex = -1;
	
        this._pointBlobCanvas = null;
        this._pointBlobBitmapWidth = 0;
        this._pointBlobBitmapHeight = 0;
        this._pointBlobTileX = 0;
        this._pointBlobTileY = 0;
        this._pointBlobStillRendering = false;    
        
        this._viewerElements = [];
        this._plusImage = null;
        this._minusImage = null;
        
        this._timelineSlider = null;
        this._timelineText = null;
        this._timelineButton = null;
        
        this._wayLayers = [];

        this._tooltipColumnIndex = -1;
        
        this._lastAnimationFrameTime = 0;
    };

    this.getXYFromLatLon = function(latLon, latLonToXYMatrix) {
        var latLonPoint = new Point(latLon.lon, this.latitudeToMercatorLatitude(latLon.lat));
	
        var result = latLonToXYMatrix.transformPoint(latLonPoint);

        return result;
    };

    this.getLatLonFromXY = function(xYPoint, xYToLatLonMatrix) {
        var latLonPoint = xYToLatLonMatrix.transformPoint(xYPoint);
	
        var result = {
			lat: this.mercatorLatitudeToLatitude(latLonPoint.y),
			lon: latLonPoint.x
        };
	
        return result;
    };
    
    this.setWayDefault = function(propertyName, propertyValue)
    {
        this._wayDefaults[propertyName] = propertyValue;
        this._dirty = true;
    };

    this.getWayProperty = function(propertyName, wayInfo)
    {
        if ((typeof wayInfo !== 'undefined') && (wayInfo.hasOwnProperty(propertyName)))
            return wayInfo[propertyName];
        else if (this._wayDefaults.hasOwnProperty(propertyName))
            return this._wayDefaults[propertyName];
        else
            return null;
    };

    this.doTagsMatch = function(tags, lineInfo)
    {
        var result = false;
        if (tags === null)
        {
            result = true;
        }
        else
        {
            if (lineInfo.hasOwnProperty('tags'))
            {
                var myTags = lineInfo.tags;
                
                for (var myTagIndex in myTags)
                {
                    var myTag = myTags[myTagIndex];
                    for (var tagIndex in tags)
                    {
                        var tag = tags[tagIndex];
                        if (myTag === tag)
                            result = true;
                    }
                }
                
            }
        }
            
        return result;
    };

    this.getTagsFromArgument = function(tagsArgument)
    {
        if (tagsArgument === null)
            return null;
		
        if (tagsArgument instanceof Array)
            return tagsArgument;
        else
            return [ tagsArgument ];
    };

    this.bind = function(eventName, functionName) {
        eventName = eventName.toLowerCase();
	
        if (eventName == 'click')
            this._onClickFunction = functionName;
        else if (eventName == 'doubleclick')
            this._onDoubleClickFunction = functionName;
        else if (eventName == 'mousedown')
            this._onMouseDownFunction = functionName;
        else if (eventName == 'mouseup')
            this._onMouseUpFunction = functionName;
        else if (eventName == 'mouseover')
            this._onMouseOverFunction = functionName;
        else if (eventName == 'mouseout')
            this._onMouseOutFunction = functionName;
        else if (eventName == 'mousemove')
            this._onMouseMoveFunction = functionName;
        else if (eventName == 'framerender')
            this._onFrameRenderFunction = functionName;
        else if (eventName == 'datachange')
            this._onDataChangeFunction = functionName;
        else if (eventName == 'waysload')
            this._onWaysLoadFunction = functionName;
        else if (eventName == 'valuesload')
            this._onValuesLoadFunction = functionName;
        else if (eventName == 'error')
            this._onErrorFunction = functionName;
        else if (eventName == 'viewchange')
            this._onViewChangeFunction = functionName;
        else
            this.logError( 'Unknown event name passed to OpenHeatMap::bind - "'+
                eventName+'" (expected click, doubleclick, mousedown, mouseup, mouseover, mouseout, framerender, datachange, waysload, valuesload, error or viewchange)');
    };

    this.setSize = function(width, height) {
        this.width = width;
        this.height = height;
        
        this._settings.width = width;
        this._settings.height = height;
        
    //	if (_timelineControls !== null)
    //		_timelineControls.setWidth(width);

        this._mainCanvas = this.createCanvas(width, height);

        this._informationLayerCanvas = this.createCanvas(width, height);

        this.repositionMoveableElements();
        
        this._dirty = true;	
    };
    
    this.setLatLonViewingArea = function(topLat, leftLon, bottomLat, rightLon) {
        topLat = this.latitudeToMercatorLatitude(topLat);
        bottomLat = this.latitudeToMercatorLatitude(bottomLat);
        
        var widthLon = (rightLon-leftLon);
        var heightLat = (bottomLat-topLat);
        
        var scaleX = (this._settings.width/widthLon);
        var scaleY = (this._settings.height/heightLat);

        var newMatrix = new Matrix();
        newMatrix.translate(-leftLon, -topLat);
        newMatrix.scale(scaleX, scaleY);

        this.setLatLonToXYMatrix(newMatrix);
    };

    this.setLatLonToXYMatrix = function (newMatrix)
    {
        this._latLonToXYMatrix = newMatrix;
        this._xYToLatLonMatrix = this._latLonToXYMatrix.clone();
        this._xYToLatLonMatrix.invert();
        
        this.updateZoomSliderDisplay();
    };

    this.makeEventArgument = function(event)
    {
        var currentPosition = this.getLocalPosition($(event.target), event.pageX, event.pageY);
        var mouseX = currentPosition.x;
        var mouseY = currentPosition.y;

        var mainLatLon = this.getLatLonFromXY(new Point(mouseX, mouseY), this._xYToLatLonMatrix);
        
        var mouseLatLon = null;
        for (var inlayIndex=0; inlayIndex<this._inlays.length; inlayIndex += 1)
        {
            var inlay = this._inlays[inlayIndex];
            
            var screenTopLeft = this.getXYFromLatLon(inlay.worldTopLeftLatLon, this._latLonToXYMatrix);
            var screenBottomRight = this.getXYFromLatLon(inlay.worldBottomRightLatLon, this._latLonToXYMatrix);

            if ((mouseX>=screenTopLeft.x)&&
                (mouseX<screenBottomRight.x)&&
                (mouseY>=screenTopLeft.y)&&
                (mouseY<screenBottomRight.y))
            {
                var localX = (mouseX-screenTopLeft.x);
                var localY = (mouseY-screenTopLeft.y);
                mouseLatLon = this.getLatLonFromXY(new Point(localX, localY), inlay.xYToLatLonMatrix);
            }
        }
        
        if (mouseLatLon === null)
            mouseLatLon = mainLatLon;
        
        var mapPointData = {};
        mapPointData.lon = mouseLatLon.lon;
        mapPointData.lat = mouseLatLon.lat;
        mapPointData.x = mouseX;
        mapPointData.y = mouseY;

        return mapPointData;
    };
	
    this.mapMouseClickHandler = function(event)
    {
        var ohmThis = event.data;
    
        if (ohmThis.isEventInTopBar(event))
            return ohmThis.onTopBarClick(event);
        
        if (!ohmThis.handleViewerElementEvent(event, 'click'))
            return false;
        
        var continueHandling;
        if (ohmThis._onClickFunction !== null)
            continueHandling = ohmThis.externalInterfaceCall(ohmThis._onClickFunction, ohmThis.makeEventArgument(event));
        else
            continueHandling = true;
            
        return true;
    };

    this.mapMouseDoubleClickHandler = function(event)
    { 
        var ohmThis = event.data;
    
        if (ohmThis.isEventInTopBar(event))
            return ohmThis.onTopBarDoubleClick(event);

        if (!ohmThis.handleViewerElementEvent(event, 'doubleclick'))
            return false;

        var continueHandling;
        if (ohmThis._onDoubleClickFunction !== null)
            continueHandling = ohmThis.externalInterfaceCall(ohmThis._onDoubleClickFunction, ohmThis.makeEventArgument(event));
        else
            continueHandling = true;
            
        if (continueHandling&&ohmThis._settings.allow_pan)
        {
            var center = ohmThis.getLocalPosition($(event.target), event.pageX, event.pageY);
            var zoomFactor = 2.0;
            
            ohmThis.zoomMapByFactorAroundPoint(zoomFactor, center, false);
            
            ohmThis.onViewChange();	
        }
            
        return true;
    };

    this.mapMouseDownHandler = function(event) 
    { 
        var ohmThis = event.data;
    
        if (ohmThis.isEventInTopBar(event))
            return ohmThis.onTopBarMouseDown(event);

        if (!ohmThis.handleViewerElementEvent(event, 'mousedown'))
            return false;

        var continueHandling;
        if (ohmThis._onMouseDownFunction !== null)
            continueHandling = ohmThis.externalInterfaceCall(ohmThis._onMouseDownFunction, ohmThis.makeEventArgument(event));
        else
            continueHandling = true;
        
        if (continueHandling&&ohmThis._settings.allow_pan)
        {
            var mousePosition = ohmThis.getLocalPosition($(event.target), event.pageX, event.pageY);

            ohmThis._isDragging = true;
            ohmThis._lastDragPosition = mousePosition; 
        }
        
        return true;
    };

    this.mapMouseUpHandler = function(event) 
    { 
        var ohmThis = event.data;
    
        if (ohmThis.isEventInTopBar(event))
            return ohmThis.onTopBarMouseUp(event);

        if (!ohmThis.handleViewerElementEvent(event, 'mouseup'))
            return false;

        var continueHandling;
        if (ohmThis._onMouseUpFunction !== null)
            continueHandling = ohmThis.externalInterfaceCall(ohmThis._onMouseUpFunction, ohmThis.makeEventArgument(event));
        else
            continueHandling = true;
        
        if (continueHandling&&ohmThis._settings.allow_pan)
        {
            if (ohmThis._isDragging)
            {
                var mousePosition = ohmThis.getLocalPosition($(event.target), event.pageX, event.pageY);
        
                var positionChange = mousePosition.subtract(ohmThis._lastDragPosition);
        
                ohmThis.translateMapByScreenPixels(positionChange.x, positionChange.y, false);
        
                ohmThis._isDragging = false;
                
                ohmThis.onViewChange();
            }
        }
        
        return true;
    };

    this.mapMouseOverHandler = function(event)
    { 
        var ohmThis = event.data;
    
        if (ohmThis.isEventInTopBar(event))
            return ohmThis.onTopBarMouseOver(event);

        if (!ohmThis.handleViewerElementEvent(event, 'mouseover'))
            return false;

        var continueHandling;
        if (ohmThis._onMouseOverFunction !== null)
            continueHandling = ohmThis.externalInterfaceCall(ohmThis._onMouseOverFunction, ohmThis.makeEventArgument(event));
        else
            continueHandling = true;
            
        return true;
    };

    this.mapMouseOutHandler = function(event)
    { 
        var ohmThis = event.data;
    
        if (ohmThis.isEventInTopBar(event))
            return ohmThis.onTopBarMouseOut(event);

        if (!ohmThis.handleViewerElementEvent(event, 'mouseout'))
            return false;

        var continueHandling;
        if (ohmThis._onMouseOutFunction !== null)
            continueHandling = ohmThis.externalInterfaceCall(ohmThis._onMouseOutFunction, ohmThis.makeEventArgument(event));
        else
            continueHandling = true;
            
        return true;
    };

    this.mapMouseMoveHandler = function(event)
    { 
        var ohmThis = event.data;
    
        if (ohmThis.isEventInTopBar(event))
            return ohmThis.onTopBarMouseMove(event);

        if (!ohmThis.handleViewerElementEvent(event, 'mousemove'))
            return false;

        var continueHandling;
        if (ohmThis._onMouseMoveFunction !== null)
            continueHandling = ohmThis.externalInterfaceCall(ohmThis._onMouseMoveFunction, ohmThis.makeEventArgument(event));
        else
            continueHandling = true;

        if (continueHandling&&ohmThis._settings.allow_pan)
        {
            if (ohmThis._isDragging)
            {
                var mousePosition = ohmThis.getLocalPosition($(event.target), event.pageX, event.pageY);
        
                var positionChange = mousePosition.subtract(ohmThis._lastDragPosition);
        
                ohmThis.translateMapByScreenPixels(positionChange.x, positionChange.y, true);
        
                ohmThis._lastDragPosition = mousePosition;
            }
        }
                
        return true;
    }

    this.doEveryFrame = function()
    {
        this._zoomSlider._isVisible = this._settings.show_zoom;
        this._plusImage._isVisible = this._settings.show_zoom;
        this._minusImage._isVisible = this._settings.show_zoom;
        	
        if (this._redrawCountdown>0)
        {
            this._redrawCountdown -= 1;
            if (this._redrawCountdown===0)
                this._dirty = true;
        }
        
        if (this._valuesDirty&&(this._redrawCountdown===0))
        {
            if (!this._hasPointValues)
            {
                this.setWaysFromValues();
                this._dirty = true;
            }
            this._valuesDirty = false;		
        }
        
        if (this._dirty||this._pointBlobStillRendering||(this._mapTilesDirty&&(this._redrawCountdown===0)))
        {		
            this.drawMapIntoMainBitmap();

            this._dirty = false;
            this._redrawCountdown = 0;
        }
        
        this.drawMainBitmapIntoViewer();
        
        this.drawViewerElements(this._canvas);

        if (this._hasTabs&&this._settings.show_tabs)
        {
            this.drawTabsIntoViewer();
        }	
        
        if (this._hasTime)
        {
            if (this._timelineButton.getIsOn()&&!this._pointBlobStillRendering)
            {
                var currentTime = new Date().getTime();
                var sinceLastFrame = (currentTime-this._lastAnimationFrameTime);
                if ((this._settings.max_fps==0)||(sinceLastFrame>(1000/this._settings.max_fps)))
                {
                    this._lastAnimationFrameTime = currentTime;

                    this._frameIndex += 1;
                    if (this._frameIndex>=this._frameTimes.length)
                    {
                        this._frameIndex = (this._frameTimes.length-1);
                        this._timelineButton.setIsOn(false);
                    }
                    
                    this.updateTimelineDisplay();
                    
                    this._dirty = true;
                    this._valuesDirty = true;
                    this.onDataChange();
                }
            }
        }

        if (this._onFrameRenderFunction !== null)
            this.externalInterfaceCall(this._onFrameRenderFunction, null);	
    };

    this.blankWay = function()
    {
        var result = {};
        
        result.boundingBox = new Rectangle();
        result.nds = [];
        result.tags = {};
        result.isClosed = false;
        
        for (var keyIndex in this._wayDefaults)
        {
            var key = this._wayDefaults[keyIndex];
            result.tags[key] = this._wayDefaults[key];
        }

        return result;	
    };

    this.onWaysLoad = function(data)
    { 	  		  	
        var waysData = $(data);
  	
        this._tagMap = {};

        var instance = this;

        waysData.find('node').each(function() {
            var newNode = {
                'lon': $(this).attr('lon'),
                'lat': $(this).attr('lat')
            };
            
            instance._nodes[$(this).attr('id')] = newNode;
        });

        waysData.find('way').each(function() {
            
            var wayId = $(this).attr('id');

            var newWay = instance.blankWay();
            newWay.id = wayId;

            var ndCount = 0;
            var firstNd = null;
            var lastNd = null;

            $(this).find('nd').each(function() {

                var ref = $(this).attr('ref');

                if (typeof instance._nodes[ref] === 'undefined')
                    return;

                ndCount += 1;
                newWay.nds.push(ref);
	  		
                if (firstNd===null)
                    firstNd = ref;
                lastNd = ref;
	  			  			
                var thisNode = instance._nodes[ref];
                var nodePos = new Point(thisNode.lon, thisNode.lat);
                newWay.boundingBox = instance.enlargeBoxToContain(newWay.boundingBox, nodePos);
            });
	  	
            newWay.isClosed = ((firstNd===lastNd)&&(!instance._settings.force_outlines));

            $(this).find('tag').each(function() {
                
                var key = $(this).attr('k');
                var value = $(this).attr('v');

                if (typeof newWay.tags[key] === 'undefined')
                {
                    newWay.tags[key] = value;				
                }
                else
                {
                    var oldValue = newWay.tags[key];
                    if (!(oldValue instanceof Array))
                    {
                        oldValue = [ oldValue ];
                    }
                    oldValue.push(value);
                    newWay.tags[key] = oldValue;
                }
	  		
                if (typeof instance._tagMap[key] === 'undefined')
                    instance._tagMap[key] = {};
	  			
                if (typeof instance._tagMap[key][value] === 'undefined')
                    instance._tagMap[key][value] = [];
	  			
                instance._tagMap[key][value].push(newWay.id);
            });

            var layerIndex;
            if (typeof newWay.tags['layer_index'] !== 'undefined')
                layerIndex = Math.min(16,Math.max(0,(Number)(newWay.tags['layer_index'])));
            else
                layerIndex = 0;

            while (instance._wayLayers.length<=layerIndex)
                instance._wayLayers.push([]);               
 		
            instance._ways[wayId] = newWay;

            instance._wayLayers[layerIndex].push(newWay);

            if (!newWay.boundingBox.isEmpty())
            {
                instance._worldBoundingBox = instance.enlargeBoxToContain(instance._worldBoundingBox, newWay.boundingBox.topLeft());
                instance._worldBoundingBox = instance.enlargeBoxToContain(instance._worldBoundingBox, newWay.boundingBox.bottomRight());
            }
        });

        this.buildWaysGrid();
        this._dirty = true;
        this._valuesDirty = true;
        if (this._onWaysLoadFunction!==null)
            this.externalInterfaceCall(this._onWaysLoadFunction, this._waysFileName);
    };
 	  
    this.loadWaysFromFile = function(waysFileName) 
    {
        // Pete - A hack to help me migrate old Flash-based data that could handle cross-domain
        waysFileName = waysFileName.replace('http://static.openheatmap.com/', '/static/');
        
        var instance = this;
        this._waysFileName = waysFileName;
        
        $.ajax({
          url: waysFileName,
          data: null,
          success: function(data) { instance.onWaysLoad(data); },
          dataType: 'text'
        });
    }

    this.decodeCSVRow = function(line, columnSeperator)
    {
        var inQuotes = false;
        var inEscape = false;
        
        var result = [];

        var currentValue = '';

        for( var i = 0; i < line.length; i+=1)
        {
            var currentChar = line.charAt(i);
        
            if (!inQuotes)
            {
                if (currentChar==='"')
                {
                    inQuotes = true;
                }
                else if (currentChar===columnSeperator)
                {
                    result.push(currentValue);
                    currentValue = '';
                }
                else
                {
                    currentValue += currentChar;
                }
            }
            else
            {
                if (!inEscape)
                {
                    if (currentChar==='\\')
                    {
                        inEscape = true;
                    }
                    else if (currentChar==='"')
                    {
                        inQuotes = false;
                    }
                    else
                    {
                        currentValue += currentChar;
                    }
                    
                }
                else
                {
                    currentValue += currentChar;
                    inEscape = false;
                }
                
            }
            
        }
        
        result.push(currentValue);
        
        return result;
    }

    this.onValuesLoad = function(data)
    {
        if (data==='')
        {
            this.logError( 'Error loading CSV file "'+this._valuesFileName+'" - empty data returned');
            return;
        }
    
        this.loadValuesFromCSVString(data);

        if (this._onValuesLoadFunction!==null)
            this.externalInterfaceCall(this._onValuesLoadFunction, this._valuesFileName);
    };

    this.loadValuesFromCSVString = function(valuesString)
    {
        var lineSeperator = '\n';
        var columnSeperator = ',';		  	

        var linesArray = valuesString.split(lineSeperator);
        
        var headerLine = linesArray[0];

        this._valueHeaders = this.decodeCSVRow(headerLine, columnSeperator);

        this._timeColumnIndex = -1;
        this._valueColumnIndex = -1;
        this._latitudeColumnIndex = -1;
        this._longitudeColumnIndex = -1;
        this._tabColumnIndex = -1;
        this._tooltipColumnIndex = -1;
        for(var headerIndex = 0; headerIndex < this._valueHeaders.length; headerIndex++ )
        {
            var header = this._valueHeaders[headerIndex].toLowerCase();
            if (header==='time')
                this._timeColumnIndex = headerIndex;	
            else if (header==='value')
                this._valueColumnIndex = headerIndex;
            else if ((header==='latitude')||(header==='lat'))
                this._latitudeColumnIndex = headerIndex;
            else if ((header==='longitude')||(header==='lon')||(header==='long'))
                this._longitudeColumnIndex = headerIndex;
            else if ((header==='tab')||(header==='category'))
                this._tabColumnIndex = headerIndex;
            else if (header==='tooltip')
                this._tooltipColumnIndex = headerIndex;
        }
        
        var hasLatitude = (this._latitudeColumnIndex!==-1);
        var hasLongitude = (this._longitudeColumnIndex!==-1);
        
        if ((hasLatitude||hasLongitude)&&(hasLatitude!=hasLongitude))
        {
            this.logError( 'Error loading CSV file "'+this._valuesFileName+'" - only found one of longitude or latitude in "'+headerLine+'"');
            return;		
        }
        
        this._hasPointValues = hasLatitude;
        this._hasTime = (this._timeColumnIndex!==-1);
        this._hasTabs = (this._tabColumnIndex!==-1);
        
        this._hasBitmapBackground = this._hasPointValues;
        
        if (!this._hasPointValues)
            this.loadAreaValues(linesArray, headerLine, columnSeperator);
        else
            this.loadPointValues(linesArray, headerLine, columnSeperator);
            
        if (this._hasTime)
        {
            this.calculateFrameTimes();
            this._frameIndex = 0;
            this.addTimelineControls();
        }
        
        this._valuesDirty = true;
        this._dirty = true;			
    };

    this.loadValuesFromFile = function(valuesFileName)
    {
        // Pete - A hack to help me migrate old Flash-based data that could handle cross-domain
        valuesFileName = valuesFileName.replace('http://data.openheatmap.com/', '/data/');

        this._valuesFileName = valuesFileName;
        var instance = this;
        $.get(valuesFileName, function(data) {
            instance.onValuesLoad(data);
        });
    };

    this.drawInformationLayer = function(canvas, width, height, latLonToXYMatrix, xYToLatLonMatrix)
    {    
        var viewingArea = this.calculateViewingArea(width, height, xYToLatLonMatrix);

        var bitmapBackground = this.drawBackgroundBitmap(width, height, viewingArea, latLonToXYMatrix, xYToLatLonMatrix);
        
        this.drawWays(canvas, width, height, viewingArea, latLonToXYMatrix, bitmapBackground);
    };

    this.drawWays = function(canvas, width, height, viewingArea, latLonToXYMatrix, bitmapBackground)
    {
        var hasBitmap = (bitmapBackground!==null);
        var bitmapMatrix = new Matrix();
        if ((this._settings.point_drawing_shape=='blob')||(this._settings.is_value_distance))
            bitmapMatrix.scale(this._settings.point_bitmap_scale, this._settings.point_bitmap_scale);
        
        var waysEmpty = true;
        for (var wayId in this._ways)
        {
            waysEmpty = false;
            break;
        }
        
        if (hasBitmap&&waysEmpty)
        {
            this.drawImage(canvas, bitmapBackground.get(0), 0, 0, width, height);
            return;
        }
        
        var context = this.beginDrawing(canvas);

        for (var layerIndex=0; layerIndex<this._wayLayers.length; layerIndex+=1)
        {
            for (var wayIndex=0; wayIndex<this._wayLayers[layerIndex].length; wayIndex+=1)
            {
                var way = this._wayLayers[layerIndex][wayIndex];
                var wayColor;
                var wayAlpha;
                if (this.getWayProperty('highlighted', way.tags)==true)
                {
                    wayColor = Number(this.getWayProperty('highlightColor', way.tags));
                    wayAlpha = Number(this.getWayProperty('highlightAlpha', way.tags));
                }
                else
                {
                    wayColor = Number(this.getWayProperty('color', way.tags));
                    wayAlpha = Number(this.getWayProperty('alpha', way.tags));
                }

                if (way.nds.length<1)
                    continue;
                
                if (!viewingArea.intersects(way.boundingBox))
                    continue;

                var isClosed = way.isClosed;

                context.beginPath();

                if (isClosed)
                {		
                    var finalNd = way.nds[way.nds.length-1];
                    var finalNode = this._nodes[finalNd];
                    
                    var finalPos = this.getXYFromLatLon(finalNode, latLonToXYMatrix);

                    if (hasBitmap)
                        context.fillStyle = context.createPattern(bitmapBackground, 'no-repeat');
                    else
                        context.fillStyle = this.colorStringFromNumber(wayColor, wayAlpha);

                    var lineColor = Number(this.getWayProperty('line_color', way.tags))
                    var lineAlpha = Number(this.getWayProperty('line_alpha', way.tags))
                    var lineThickness = Number(this.getWayProperty('line_thickness', way.tags))

                    if (lineAlpha>=0.01)
                    {
                        context.strokeStyle = this.colorStringFromNumber(lineColor,lineAlpha);
                        context.lineWidth = lineThickness;
                    }
                    
                    context.moveTo(finalPos.x, finalPos.y);
                }
                else
                {
                    var firstNd = way.nds[0];
                    var firstNode = this._nodes[firstNd];
                    
                    var firstPos = this.getXYFromLatLon(firstNode, latLonToXYMatrix);

                    context.strokeStyle = this.colorStringFromNumber(wayColor,wayAlpha);

                    context.moveTo(firstPos.x, firstPos.y);
                }

                for (var currentNdIndex=0; currentNdIndex<way.nds.length; currentNdIndex+=1)
                {
                    var currentNd = way.nds[currentNdIndex];
                    var currentNode = this._nodes[currentNd];
                    var currentPos = this.getXYFromLatLon(currentNode, latLonToXYMatrix);
                    
                    context.lineTo(currentPos.x, currentPos.y);
                }

                context.closePath();

                if (isClosed)
                {
                    context.fill();
                    if (lineAlpha>=0.01)
                        context.stroke();
                }
                else
                {
                    context.stroke();
                }
            }
        }
        
        this.endDrawing(context);
    };

    this.setWaysFromValues = function()
    {	
        if (this._valueData === null)
            return;

        if (this._settings.is_gradient_value_range_set)
        {
            var minValue = this._settings.gradient_value_min;
            var maxValue = this._settings.gradient_value_max;	
        }
        else
        {
            minValue = this._smallestValue;
            maxValue = this._largestValue;
        }
        if (Math.abs(maxValue-minValue)<0.00001)	
            minValue = (maxValue-1.0);
        var valueScale = (1.0/(maxValue-minValue));

        var currentValues = this.getCurrentValues();
        
        var thisSetWayIds = {};
        
        if (this._hasTime)
            var currentTime = this._frameTimes[this._frameIndex];
        
        for (var valuesIndex in currentValues)
        {
            var values = currentValues[valuesIndex];
            if (this._hasTime)
            {
                var thisTime = values[this._timeColumnIndex];
                if (thisTime !== currentTime)
                    continue;
            }

            var matchKeys = {};
            var thisValue = 0;		
            for (var i = 0; i<values.length; i+=1)
            {
                if (i===this._valueColumnIndex)
                {
                    thisValue = values[i];
                }
                else if ((i!==this._timeColumnIndex)&&(i!==this._tabColumnIndex)&&(i!==this._tooltipColumnIndex))
                {
                    var headerName = this._valueHeaders[i];
                    matchKeys[headerName] = values[i];	
                }
            }
            
            var setColor = this.getColorForValue(thisValue, minValue, maxValue, valueScale);
            
            this.setAttributeForMatchingWays(matchKeys, 'color', setColor, thisSetWayIds, valuesIndex);
        }
        
        if (this._settings.clear_ways)
        {
            var defaultColor = this.getWayProperty('color');
            
            for (var lastWayId in this._lastSetWayIds)
            {
                if (thisSetWayIds.hasOwnProperty(lastWayId))
                    continue;
                    
                this._ways[lastWayId]['tags']['color'] = defaultColor;
            }
        }
        
        this._lastSetWayIds = thisSetWayIds;
    };

    this.setColorGradient = function(colorList)
    {
        this._colorGradient = [];
        
        for (var colorStringIndex=0; colorStringIndex<colorList.length; colorStringIndex+=1)
        {
            var colorString = colorList[colorStringIndex];
            colorString = colorString.replace('#', '0x');
            
            var colorNumber = Math.floor(colorString);
            
            var alpha;
            if (colorString.length>8)
                alpha = (colorNumber>>24)&0xff;
            else
                alpha = 0x7f;		
            
            var red = (colorNumber>>16)&0xff;
            var green = (colorNumber>>8)&0xff;
            var blue = (colorNumber>>0)&0xff;
            
            var premultRed = Math.floor((red*alpha)/255.0);
            var premultGreen = Math.floor((green*alpha)/255.0);
            var premultBlue = Math.floor((blue*alpha)/255.0);
            
            this._colorGradient.push({
                alpha: alpha,
                red: premultRed,
                green: premultGreen,
                blue: premultBlue
            });
        }

        this._valuesDirty = true;
        this._redrawCountdown = 5;
    }

    this.setAttributeForMatchingWays = function(matchKeys, attributeName, attributeValue, setWays, valueIndex)
    {
        var matchingWayIds = null;
        for (var key in matchKeys)
        {
            var value = matchKeys[key];
            
            var currentMatches;
            if (!this._tagMap.hasOwnProperty(key)||!this._tagMap[key].hasOwnProperty(value))
                currentMatches = [];
            else
                currentMatches = this._tagMap[key][value];
             
            if (matchingWayIds === null)
            {
                matchingWayIds = {};
                for (var wayIdIndex=0; wayIdIndex<currentMatches.length; wayIdIndex+=1)
                {
                    var wayId = currentMatches[wayIdIndex];
                    matchingWayIds[wayId] = true;
                }
            }
            else
            {
                var previousMatchingWayIds = matchingWayIds;
                matchingWayIds = {};
                for (var wayIdIndex=0; wayIdIndex<currentMatches.length; wayIdIndex+=1)
                {
                    var wayId = currentMatches[wayIdIndex];
                    if (typeof previousMatchingWayIds[wayId] !== 'undefined')
                        matchingWayIds[wayId] = true;
                }
            }
        }
            
        var foundCount = 0;
        for (wayId in matchingWayIds)
        {
            var wayTags = this._ways[wayId]['tags'];
            wayTags[attributeName] = attributeValue;
            wayTags['valueIndex'] = valueIndex;
            foundCount += 1;
            setWays[wayId] = true;
        }

    //	if (foundCount===0)
    //	{
    //		trace('No match found for');
    //		for (key in matchKeys)
    //		{
    //			value = matchKeys[key];	
    //			trace(key+':'+value);
    //		}
    //	}

    };

    this.enlargeBoxToContain = function(box, pos)
    {
        if (box.containsPoint(pos))
            return box;
	
        if ((box.x==0)&&
            (box.y==0)&&
            (box.width==0)&&
            (box.height==0))
            return new Rectangle(pos.x, pos.y, 0, 0);
		
        if (box.left()>pos.x)
            box.left(pos.x);

        if (box.right()<pos.x)
            box.right(pos.x);

        if (box.top()>pos.y)
            box.top(pos.y);
            
        if (box.bottom()<pos.y)
            box.bottom(pos.y);
            
        return box;
    };

    this.buildWaysGrid = function()
    {
        this._waysGrid = new BucketGrid(this._worldBoundingBox, 16, 16);
        
        for (var wayId in this._ways)
        {
            var way = this._ways[wayId];

            var boundingBox = way.boundingBox;
            if (boundingBox.isEmpty())
                continue;
            
            this._waysGrid.insertObjectAt(boundingBox, wayId);
        }
    };

    this.getWaysContainingLatLon = function(lat, lon)
    {
        var result = [];

        var pos = new Point(lon, lat);

        if (!this._worldBoundingBox.containsPoint(pos))
            return result;
        
        if (this._waysGrid===null)
            return result;
        
        var pixelsPerDegree = this.getPixelsPerDegreeLatitude();
        var pixelsToDegreeScale = (1.0/pixelsPerDegree);
        var ways = this._waysGrid.getContentsAtPoint(pos);

        var currentValues = this.getCurrentValues();
        
        for (var wayIdIndex in ways)
        {
            var wayId = ways[wayIdIndex];
            
            var way = this._ways[wayId];
            var isInside = false;
            if (way.isClosed)
            {
                if (way.boundingBox.containsPoint(pos))
                {
                    isInside = this.isPointInsideClosedWay(pos, way);
                }
            }
            else
            {
                var lineThickness = (Number)(this.getWayProperty('line_thickness', way));
                
                var thicknessInDegrees = Math.abs((lineThickness+1)*pixelsToDegreeScale);
                
                var boundingBox = way.boundingBox.clone();
    //			boundingBox.inflate(thicknessInDegrees/2, thicknessInDegrees/2);
                
                if (boundingBox.containsPoint(pos))
                {
                    isInside = this.isPointOnWayLine(pos, way, thicknessInDegrees);	
                }			
            }
            
            if (isInside)
            {
                var wayResult = {};
                wayResult.id = wayId;
                wayResult.tags = {};

                if (typeof way.tags['valueIndex'] != 'undefined')
                {			
                    var valueIndex = way.tags['valueIndex'];
                    var valuesRow = currentValues[valueIndex];

                    for (var headerIndex = 0; headerIndex < this._valueHeaders.length; headerIndex++)
                    {
                        var header = this._valueHeaders[headerIndex].toLowerCase();

                        wayResult.tags[header] = valuesRow[headerIndex];
                    }
                }

                for (var key in way.tags)
                {
                    // Pete - Safari really doesn't like colons in member names! 
                    key = key.replace(':', '_colon_');
                    var value = way.tags[key];
                    wayResult.tags[key] = value;
                }
                
                result.push(wayResult);
            }
        }
        
        return result;
    };

    this.addTimelineControls = function()
    {
        if (this._timelineSlider === null)
        {
            var instance = this;
            this._timelineSlider = new Slider(
                80, (this._settings.height-30),
                (this._settings.width-250), 10,
                function(isDragging) { instance.onTimelineSliderChange(isDragging) });
        
            this.addChild(this._timelineSlider);
            
            this._timelineText = new UIText('', '18px Baskerville, Times New Roman, Serif', 
                (this._settings.width-160), (this._settings.height-38));
            this.addChild(this._timelineText);
            
            this._timelineButton = new UIButton(
                40, (this._settings.height-39),
                32, 32,
                'http://static.openheatmap.com/images/pause.png',
                'http://static.openheatmap.com/images/play.png',
                function(myInstance) { 
                    return function(button) {
                        var totalFrames = myInstance._frameTimes.length;
                        if ((button._isOn)&&(myInstance._frameIndex==(totalFrames-1)))
                        {
                            myInstance._frameIndex = 0;
                        }
                    } 
                }(instance)
                );
            this.addChild(this._timelineButton);
        }
        
        this.updateTimelineDisplay();
    };

    this.onTimelineSliderChange = function(dragging)
    {
        var sliderValue = this._timelineSlider.getSliderValue();

        var totalFrames = this._frameTimes.length;

        this._frameIndex = Math.round(sliderValue*(totalFrames-1));
        this._frameIndex = Math.min(this._frameIndex, (totalFrames-1));
        this._frameIndex = Math.max(this._frameIndex, 0);
        
        this.updateTimelineDisplay();
        
        if (dragging)
            this._redrawCountdown = 5;
        else
            this._dirty = true;
            
        this._valuesDirty = true;
        this.onDataChange();
    };

    this.updateTimelineDisplay = function()
    {
        if (this._frameTimes.length>0)
        {
            var currentTime = this._frameTimes[this._frameIndex];
            this._timelineText.setText(currentTime);
            
            var totalFrames = this._frameTimes.length;
            this._timelineSlider.setSliderValue(this._frameIndex/(totalFrames-1));
        }
    };

    this.getValueForWayId = function(wayId)
    {
        if (typeof this._ways[wayId] === 'undefined')
            return null;
            
        var way = this._ways[wayId];

        if (this._valueData === null)
            return null;

        var currentValues = this.getCurrentValues();
        
        var resultFound = false;
        var result;
        for (var valuesIndex in currentValues)
        {
            var values = currentValues[valuesIndex];
            
            var matchKeys = {};
            var thisValue = null;		
            for (var i = 0; i<values.length; i+=1)
            {
                if (i===this._valueColumnIndex)
                {
                    thisValue = values[i];
                }
                else if ((i!==this._timeColumnIndex)&&(i!==this._tabColumnIndex)&&(i!==this._tooltipColumnIndex))
                {
                    var headerName = this._valueHeaders[i];
                    matchKeys[headerName] = values[i];	
                }
            }
            
            var allMatch = true;
            var emptyMatchKeys = true;
            for (var key in matchKeys)
            {
                var value = matchKeys[key];
                
                var wayValue = way.tags[key];
                if (wayValue instanceof Array)
                {
                    var anyMatch = false;
                    for (var wayValueIndex = 0; wayValueIndex<wayValue.length; wayValueIndex+=1)
                    {
                        var subValue = wayValue[wayValueIndex];
                        if (subValue==value)
                            anyMatch = true;
                    }
                    if (!anyMatch)
                        allMatch = false;
                }
                else
                {
                    if (way.tags[key]!==value)
                        allMatch = false;
                }
                    
                emptyMatchKeys = false;
            }
            
            if (allMatch && !emptyMatchKeys)
            {
                resultFound = true;
                result = thisValue;
            }
        }

        if (resultFound)
            return result;
        else
            return null;
    };

    this.addInlay = function(leftX, topY, rightX, bottomY, topLat, leftLon, bottomLat, rightLon)
    {
        var mercatorTopLat = this.latitudeToMercatorLatitude(topLat);
        var mercatorBottomLat = this.latitudeToMercatorLatitude(bottomLat);
        
        var width = (rightX-leftX);
        var height = (bottomY-topY);
        
        var widthLon = (rightLon-leftLon);
        var heightLat = (mercatorBottomLat-mercatorTopLat);
        
        var scaleX = (width/widthLon);
        var scaleY = (height/heightLat);

        var latLonToXYMatrix = new Matrix();
        latLonToXYMatrix.translate(-leftLon, -mercatorTopLat);
        latLonToXYMatrix.scale(scaleX, scaleY);	

        var xYToLatLonMatrix = latLonToXYMatrix.clone();
        xYToLatLonMatrix.invert();
        
        var worldTopLeftLatLon = this.getLatLonFromXY(new Point(leftX, topY), this._xYToLatLonMatrix);
        var worldBottomRightLatLon = this.getLatLonFromXY(new Point(rightX, bottomY), this._xYToLatLonMatrix);
        
        this._inlays.push({
            latLonToXYMatrix: latLonToXYMatrix,
            xYToLatLonMatrix: xYToLatLonMatrix,
            worldTopLeftLatLon: worldTopLeftLatLon,
            worldBottomRightLatLon: worldBottomRightLatLon,
            topLat: topLat,
            leftLon: leftLon,
            bottomLat: bottomLat,
            rightLon: rightLon
        });
    };

    this.cropPoint = function(input, area)
    {
        var result = input.clone();
        
        if (result.x<area.left)
            result.x = area.left;
        
        if (result.x>area.right)
            result.x = area.right;	
        
        if (result.y<area.top)
            result.y = area.top;
        
        if (result.y>area.bottom)
            result.y = area.bottom;	

        return result;	
    };

    this.drawMapIntoMainBitmap = function()
    {
        this.clearCanvas(this._mainCanvas);
        this.fillRect(this._mainCanvas, 0, 0, this._settings.width, this._settings.height, this._settings.ocean_color);

        if (this._settings.show_map_tiles)
        {
    		this.trackMapTilesUsage();
            this.drawMapTiles(this._mainCanvas, this._settings.width, this._settings.height, this._latLonToXYMatrix, this._xYToLatLonMatrix);
        }

        if (this._dirty||this._pointBlobStillRendering)
        {			
            this.clearCanvas(this._informationLayerCanvas);
            this.drawInformationLayer(this._informationLayerCanvas, this._settings.width, this._settings.height, this._latLonToXYMatrix, this._xYToLatLonMatrix);
        }

        this.drawImage(this._mainCanvas, this._informationLayerCanvas.get(0), 0, 0, this._settings.width, this._settings.height);
                
        for (var inlayIndex=0; inlayIndex<this._inlays.length; inlayIndex+=1)
        {
            var inlay = this._inlays[inlayIndex];
            
            var screenTopLeft = this.getXYFromLatLon(inlay.worldTopLeftLatLon, this._latLonToXYMatrix);
            var screenBottomRight = this.getXYFromLatLon(inlay.worldBottomRightLatLon, this._latLonToXYMatrix);
            
            var screenArea = new Rectangle(0, 0, this._settings.width, this._settings.height);
            
            var croppedScreenTopLeft = this.cropPoint(screenTopLeft, screenArea);
            var croppedScreenBottomRight = this.cropPoint(screenBottomRight, screenArea);
            
            var inlayWidth = (croppedScreenBottomRight.x-croppedScreenTopLeft.x);
            var inlayHeight = (croppedScreenBottomRight.y-croppedScreenTopLeft.y);
            
            if ((inlayWidth<1)||(inlayHeight<1))
                continue;
            
            var inlayScreenLeftX = croppedScreenTopLeft.x;
            var inlayScreenTopY = croppedScreenTopLeft.y;
            
            var localTopLeft = croppedScreenTopLeft.subtract(screenTopLeft);

            var croppedLatLonToXYMatrix = inlay.latLonToXYMatrix.clone();
            croppedLatLonToXYMatrix.translate(-localTopLeft.x, -localTopLeft.y);
            
            var croppedXYToLatLonMatrix = croppedLatLonToXYMatrix.clone();
            croppedXYToLatLonMatrix.invert();
            
            drawingSurface = this.createCanvas(inlayWidth, inlayHeight);
            
            if (this._settings.show_map_tiles)	
                this.drawMapTiles(drawingSurface, inlayWidth, inlayHeight, croppedLatLonToXYMatrix, croppedXYToLatLonMatrix);

            if (this._dirty||this._pointBlobStillRendering)
            {			
                inlay._informationLayerCanvas = this.createCanvas(inlayWidth, inlayHeight);
                this.drawInformationLayer(inlay._informationLayerCanvas, inlayWidth, inlayHeight, croppedLatLonToXYMatrix, croppedXYToLatLonMatrix);
            }
            
            this.drawImage(drawingSurface, inlay._informationLayerCanvas.get(0), 0, 0, inlayWidth, inlayHeight);
            
            var borderTopLeft = screenTopLeft.subtract(croppedScreenTopLeft);
            var borderBottomRight = screenBottomRight.subtract(croppedScreenTopLeft).subtract(new Point(1, 1));
            
            borderTopLeft.x = Math.floor(borderTopLeft.x);
            borderTopLeft.y = Math.floor(borderTopLeft.y);
            
            borderBottomRight.x = Math.floor(borderBottomRight.x);
            borderBottomRight.y = Math.floor(borderBottomRight.y);
            
            if (this._settings.show_map_tiles)
            {
                var context = this.beginDrawing(drawingSurface);
                context.lineWidth = 1.0;
                context.strokeStyle = this.colorStringFromNumber(this._settings.inlay_border_color, 1.0);

                context.beginPath();
                context.moveTo(borderTopLeft.x, borderTopLeft.y);
                context.lineTo(borderBottomRight.x, borderTopLeft.y);
                context.lineTo(borderBottomRight.x, borderBottomRight.y);
                context.lineTo(borderTopLeft.x, borderBottomRight.y);
                context.lineTo(borderTopLeft.x, borderTopLeft.y);
                context.closePath();
                context.stroke();
                
                this.endDrawing(context);
            }
        
            this.drawImage(this._mainCanvas, drawingSurface.get(0), inlayScreenLeftX, inlayScreenTopY, inlayWidth, inlayHeight);
        }

        this._mainBitmapTopLeftLatLon = this.getLatLonFromXY(new Point(0, 0), this._xYToLatLonMatrix);
        this._mainBitmapBottomRightLatLon = this.getLatLonFromXY(new Point(this._settings.width, this._settings.height), this._xYToLatLonMatrix);

        if (this._settings.show_map_tiles)
        {
            this.deleteUnusedMapTiles();
        }
    };

    this.drawMainBitmapIntoViewer = function()
    {
        this.clearCanvas(this._canvas);
        
        if ((this._mainBitmapTopLeftLatLon===null)||
            (this._mainBitmapBottomRightLatLon===null))
            return;
            
        var screenBitmapTopLeft = this.getXYFromLatLon(this._mainBitmapTopLeftLatLon, this._latLonToXYMatrix);
        var screenBitmapBottomRight = this.getXYFromLatLon(this._mainBitmapBottomRightLatLon, this._latLonToXYMatrix);	

        var screenBitmapLeft = screenBitmapTopLeft.x;
        var screenBitmapTop = screenBitmapTopLeft.y;
        
        var screenBitmapWidth = (screenBitmapBottomRight.x-screenBitmapTopLeft.x);
        var screenBitmapHeight = (screenBitmapBottomRight.y-screenBitmapTopLeft.y);
        
        this.drawImage(this._canvas, this._mainCanvas.get(0), screenBitmapLeft, screenBitmapTop, screenBitmapWidth, screenBitmapHeight);
    };

    this.translateMapByScreenPixels = function(x, y, dragging)
    {
        this._latLonToXYMatrix.translate(x, y);
        this._xYToLatLonMatrix = this._latLonToXYMatrix.clone();
        this._xYToLatLonMatrix.invert();
        
        if (dragging)
            this._redrawCountdown = 5;
        else
            this._dirty = true;
    };

    this.zoomMapByFactorAroundPoint = function(zoomFactor, center, dragging)
    {
        var translateToOrigin = new Matrix();
        translateToOrigin.translate(-center.x, -center.y);
        
        var scale = new Matrix();
        scale.scale(zoomFactor, zoomFactor);
        
        var translateFromOrigin = new Matrix();
        translateFromOrigin.translate(center.x, center.y);

        var zoom = new Matrix();
        zoom.concat(translateToOrigin);
        zoom.concat(scale);
        zoom.concat(translateFromOrigin);
        
        this._latLonToXYMatrix.concat(zoom);
        this._xYToLatLonMatrix = this._latLonToXYMatrix.clone();
        this._xYToLatLonMatrix.invert();

        for (var inlayIndex=0; inlayIndex<this._inlays.length; inlayIndex+=1)
        {
            var inlay = this._inlays[inlayIndex];
            var newLatLonToXYMatrix = inlay.latLonToXYMatrix.clone();
            newLatLonToXYMatrix.concat(scale);
            
            var newXYToLatLonMatrix = newLatLonToXYMatrix.clone();
            newXYToLatLonMatrix.invert();
            
            inlay.latLonToXYMatrix = newLatLonToXYMatrix;
            inlay.xYToLatLonMatrix = newXYToLatLonMatrix;
        }
        
        if (dragging)
            this._redrawCountdown = 5;
        else
            this._dirty = true;
            
        this.updateZoomSliderDisplay();
    };

    this.createViewerElements = function()
    {
        this._viewerElements = [];

        this._mainCanvas = this.createCanvas(this._settings.width, this._settings.height);

        this._informationLayerCanvas = this.createCanvas(this._settings.width, this._settings.height);

        this._plusImage = new UIImage('http://static.openheatmap.com/images/plus.gif', 10, 35);
        this.addChild(this._plusImage);

        this._minusImage = new UIImage('http://static.openheatmap.com/images/minus.gif', 10, 197);
        this.addChild(this._minusImage);
        
        var instance = this;
        
        this._zoomSlider = new Slider(15, 50, 10, 150, 
            function(isDragging) { instance.onZoomSliderChange(isDragging); });
        this.addChild(this._zoomSlider);

        this._credit = new UIText(
            this._settings.credit_text,
            '11px Baskerville, Times New Roman, Serif',
            0, 0,
            function() { window.open('http://openheatmap.com', '_blank'); }
        );
        this.addChild(this._credit);

        this._title = new UIText(
            this._settings.title_text,
            '16px Baskerville, Times New Roman, Serif',
            0, -1000,
            null,
            'center');
        this._title.setBackground(
            this._settings._width, (this._settings.title_size*1.5),
            this.colorStringFromNumber(this._settings.title_background_color));
                    
        this.addChild(this._title);

        this.repositionMoveableElements();
    };

    this.onZoomSliderChange = function(isDragging)
    {
        var pixelsPerDegreeLatitude = this.calculatePixelsPerDegreeLatitudeFromZoomSlider();
	
        this.setPixelsPerDegreeLatitude(pixelsPerDegreeLatitude, isDragging);

        this.onViewChange();
    };

    this.getPixelsPerDegreeLatitude = function()
    {
        var pixelsPerDegreeLatitude = this._latLonToXYMatrix.d;
	
        return pixelsPerDegreeLatitude;
    };

    this.setPixelsPerDegreeLatitude = function(newPixelsPerDegreeLatitude, dragging)
    {
        var oldPixelsPerDegreeLatitude = this.getPixelsPerDegreeLatitude();
        
        var zoomFactor = (newPixelsPerDegreeLatitude/oldPixelsPerDegreeLatitude);
        
        var center = new Point((this._settings.width/2), (this._settings.height/2));
        
        this.zoomMapByFactorAroundPoint(zoomFactor, center, dragging);
    }

    this.calculatePixelsPerDegreeLatitudeFromZoomSlider = function()
    {
        var sliderValue = this._zoomSlider.getSliderValue();
        
        var lerpValue = Math.pow(sliderValue, this._settings.zoom_slider_power);

        var minPixelsPerDegreeLatitude = (this._settings.height/this._settings.zoomed_out_degrees_per_pixel);
        var maxPixelsPerDegreeLatitude = (this._settings.height/this._settings.zoomed_in_degrees_per_pixel);

        var oneMinusLerp = (1-lerpValue);
        
        var result = (minPixelsPerDegreeLatitude*oneMinusLerp)+
            (maxPixelsPerDegreeLatitude*lerpValue);
        
        return result;
    };

    this.updateZoomSliderDisplay = function()
    {
        var pixelsPerDegreeLatitude = this.getPixelsPerDegreeLatitude();

        var minPixelsPerDegreeLatitude = (this._settings.height/this._settings.zoomed_out_degrees_per_pixel);
        var maxPixelsPerDegreeLatitude = (this._settings.height/this._settings.zoomed_in_degrees_per_pixel);

        var lerpValue = ((pixelsPerDegreeLatitude-minPixelsPerDegreeLatitude)/
            (maxPixelsPerDegreeLatitude-minPixelsPerDegreeLatitude));
        
        var sliderValue = Math.pow(lerpValue, (1/this._settings.zoom_slider_power));

        this._zoomSlider.setSliderValue(sliderValue);
    };

    this.setGradientValueRange = function(min, max)
    {
        this._settings.is_gradient_value_range_set = true;
        this._settings.gradient_value_min = min;
        this._settings.gradient_value_max = max;
    };

    this.calculateFrameTimes = function()
    {
        this._frameTimes = [];
        
        for (var thisTime in this._foundTimes)
        {
            if ((this._settings.time_range_start!==null)&&(thisTime<this._settings.time_range_start))
                continue;

            if ((this._settings.time_range_end!==null)&&(thisTime>this._settings.time_range_end))
                continue;
            
            this._frameTimes.push(thisTime);
        }
        this._frameTimes.sort();
        
        if (this._frameIndex>(this._frameTimes.length-1))
            this._frameIndex = (this._frameTimes.length-1);
    };

    this.onDataChange = function()
    {
        if (this._onDataChangeFunction!==null)
            this.externalInterfaceCall(this._onDataChangeFunction, null);	
    };

    this.logError = function(message) {
        alert('Error: '+message);
        if (this._onErrorFunction!==null)
            this.externalInterfaceCall(this._onErrorFunction, message);	
    };

    this.onViewChange = function()
    {
        if (this._onViewChangeFunction!==null)
            this.externalInterfaceCall(this._onViewChangeFunction, null);	
    };

    this.getWayForWayId = function(wayId)
    {
        var result = this._ways[wayId];
        
        return result;	
    };

    this.isPointInsideClosedWay = function(pos, way)
    {
        var xIntersections = [];

        var lineStart = null;
        var isFirst = true;
        
        for (var currentNdIndex=0; currentNdIndex<way.nds.length; currentNdIndex+=1)
        {
            var currentNd = way.nds[currentNdIndex];
            
            var currentNode = this._nodes[currentNd];
            var lineEnd = new Point(currentNode.lon, currentNode.lat);
            
            if (isFirst)
            {
                isFirst = false;
            }
            else
            {
                if (((lineStart.y>pos.y)&&(lineEnd.y<pos.y))||
                    ((lineStart.y<pos.y)&&(lineEnd.y>pos.y)))
                {
                    var lineDirection = new Point(lineEnd.x-lineStart.x, lineEnd.y-lineStart.y);
                    var yDelta = (pos.y-lineStart.y);
                    var yProportion = (yDelta/lineDirection.y);
                    
                    var xIntersect = (lineStart.x+(lineDirection.x*yProportion));
                    xIntersections.push(xIntersect);
                }
                
            }
            
            lineStart = lineEnd;
        }
        
        xIntersections.sort(function(a, b) {
            if (a<b) return -1;
            else if (a>b) return 1;
            else return 0; 
        });
        
        var isInside = false;
        for (var index = 0; index<(xIntersections.length-1); index += 2)
        {
            var leftX = xIntersections[index];
            var rightX = xIntersections[(index+1)];

            if ((leftX<=pos.x)&&(rightX>pos.x))
                isInside = true;
            
        }
                    
        return isInside;
    }

    this.isPointOnWayLine = function(pos, way, thickness)
    {
        var lineStart = null;
        var isFirst = true;
        
        var thicknessSquared = (thickness*thickness);
        
        var isInside = false;
        for (var currentNdIndex=0; currentNdIndex<way.nds.length; currentNdIndex+=1)
        {
            var currentNd = way.nds[currentNdIndex];
            
            var currentNode = this._nodes[currentNd];
            var lineEnd = new Point(currentNode.lon, currentNode.lat);
            
            if (isFirst)
            {
                isFirst = false;
            }
            else
            {
                var lineDirection = new Point(lineEnd.x-lineStart.x, lineEnd.y-lineStart.y);
                
                var lineDirectionSquared = ((lineDirection.x*lineDirection.x)+(lineDirection.y*lineDirection.y));
                
                var s = ((pos.x-lineStart.x)*lineDirection.x)+((pos.y-lineStart.y)*lineDirection.y);
                s /= lineDirectionSquared;
                
                s = Math.max(s, 0);
                s = Math.min(s, 1);
                
                var closestPoint = new Point((lineStart.x+s*lineDirection.x), (lineStart.y+s*lineDirection.y));
                
                var delta = pos.subtract(closestPoint);
                
                var distanceSquared = ((delta.x*delta.x)+(delta.y*delta.y));
                
                if (distanceSquared<thicknessSquared)
                {
                    isInside = true;
                    break;
                }
            }
            
            lineStart = lineEnd;
        }
        
        return isInside;
    };

    this.drawPointBlobBitmap = function(width, height, viewingArea, latLonToXYMatrix, xYToLatLonMatrix)
    {
        if (!this._hasPointValues)
            return null;

        if ((this._redrawCountdown>0)&&(!this._dirty))
            return null;
        
        if (this._dirty)
        {
            this.createPointsGrid(viewingArea, latLonToXYMatrix);
        
            this._pointBlobBitmapWidth = (width/this._settings.point_bitmap_scale);
            this._pointBlobBitmapHeight = (height/this._settings.point_bitmap_scale);
        
            this._pointBlobCanvas = this.createCanvas(this._pointBlobBitmapWidth, this._pointBlobBitmapHeight);
            
            this._pointBlobTileX = 0;
            this._pointBlobTileY = 0;
            
            this._pointBlobStillRendering = true;
        }

        var tileSize = this._settings.point_blob_tile_size;	

        var startTime = new Date().getTime();
        
        while (this._pointBlobTileY<this._pointBlobBitmapHeight)
        {
            var distanceFromBottom = (this._pointBlobBitmapHeight-this._pointBlobTileY);
            var tileHeight = Math.min(tileSize, distanceFromBottom);
            
            while (this._pointBlobTileX<this._pointBlobBitmapWidth)
            {	
                var distanceFromRight = (this._pointBlobBitmapWidth-this._pointBlobTileX);
                var tileWidth = Math.min(tileSize, distanceFromRight);
                
                this.drawPointBlobTile(width, height, viewingArea, latLonToXYMatrix, xYToLatLonMatrix, this._pointBlobTileX, this._pointBlobTileY, tileWidth, tileHeight);
                
                this._pointBlobTileX+=tileSize;

                var currentTime = new Date().getTime();
                var sinceStart = (currentTime-startTime);
			
                if ((this._timelineButton===null)||(!this._timelineButton.getIsOn()))
                {
                    if (sinceStart>2000)
                        return this._pointBlobCanvas;
                }
            }
            
            this._pointBlobTileX = 0;
            this._pointBlobTileY+=tileSize
        }
        
        this._pointBlobStillRendering = false;
        
        return this._pointBlobCanvas;
    };

    this.loadAreaValues = function(linesArray, headerLine, columnSeperator)
    {
        if (this._valueColumnIndex===-1)
        {
            this.logError( 'Error loading CSV file "'+this._valuesFileName+'" - missing value column from header "'+headerLine+'"');
            return;
        }
        
        this._foundTimes = {};
        this._tabNames = [];
        this._tabInfo = {};
        
        this._valueData = [];
        
        for(var i = 1; i < linesArray.length; i++ )
        {
            var lineString = linesArray[i];
            var lineValues = this.decodeCSVRow(lineString, columnSeperator);
            
            var thisValue = (Number)(lineValues[this._valueColumnIndex]);
            
            if ((i===1)||(thisValue<this._smallestValue))
                this._smallestValue = thisValue;
                
            if ((i===1)||(thisValue>this._largestValue))
                this._largestValue = thisValue;
            
            var dataDestination = this._valueData;

            if (this._hasTabs)
            {
                var thisTab = lineValues[this._tabColumnIndex];
                if ((thisTab !== null)&&(thisTab !== '')&&(typeof thisTab !== 'undefined'))
                {
                    if (typeof this._tabInfo[thisTab] === 'undefined')
                    {
                        this._tabInfo[thisTab] = {};
                        this._tabNames.push(thisTab);
                    }
                    
                    if (typeof dataDestination[thisTab]==='undefined')
                    {
                        dataDestination[thisTab] = [];
                    }
                    
                    dataDestination = dataDestination[thisTab];
                }			
            }		
            
            if (this._hasTime)
            {
                var thisTime = lineValues[this._timeColumnIndex];
                if ((thisTime !== null)&&(thisTime!=''))
                {
                    if (typeof this._foundTimes[thisTime] === 'undefined')
                    {
                        this._foundTimes[thisTime] = true;
                    }
                    
                    if (typeof dataDestination[thisTime] === 'undefined')
                    {				
                        dataDestination[thisTime] = [];
                    }

                    dataDestination = dataDestination[thisTime];
                }
            }

            dataDestination.push(lineValues);	
        }
        
    };

    this.loadPointValues = function(linesArray, headerLine, columnSeperator)
    {	
        this._foundTimes = {};
        this._tabInfo = {};
        this._tabNames = [];
            
        this._valueData = [];
        
        for(var i = 1; i < linesArray.length; i++ )
        {
            var lineString = linesArray[i];
            var lineValues = this.decodeCSVRow(lineString, columnSeperator);
            
            var thisLatitude = (Number)(lineValues[this._latitudeColumnIndex]);
            var thisLongitude = (Number)(lineValues[this._longitudeColumnIndex]);

            if (isNaN(thisLatitude)||isNaN(thisLongitude))
                continue;

            lineValues[this._latitudeColumnIndex] = thisLatitude;
            lineValues[this._longitudeColumnIndex] = thisLongitude;

            if (this._valueColumnIndex!==-1)
            {
                var thisValue = (Number)(lineValues[this._valueColumnIndex]);
                lineValues[this._valueColumnIndex] = thisValue;
                
                if ((i===1)||(thisValue<this._smallestValue))
                    this._smallestValue = thisValue;
                
                if ((i===1)||(thisValue>this._largestValue))
                    this._largestValue = thisValue;
            }
            
            var dataDestination = this._valueData;
            
            if (this._hasTabs)
            {
                var thisTab = lineValues[this._tabColumnIndex];
                if ((thisTab !== null)&&(thisTab !== '')&&(typeof thisTab !== 'undefined'))
                {
                    if (typeof this._tabInfo[thisTab] === 'undefined')
                    {
                        this._tabInfo[thisTab] = {};
                        this._tabNames.push(thisTab);
                    }
                    if (typeof dataDestination[thisTab] === 'undefined')
                    {
                        dataDestination[thisTab] = [];
                    }
                    
                    dataDestination = dataDestination[thisTab];
                }			
            }		
            
            if (this._hasTime)
            {
                var thisTime = lineValues[this._timeColumnIndex];
                if ((thisTime !== null)&&(thisTime!=''))
                {
                    if (typeof this._foundTimes[thisTime] === 'undefined')
                    {
                        this._foundTimes[thisTime] = true;
                    }
                    if (typeof dataDestination[thisTime] === 'undefined')
                    {
                        dataDestination[thisTime] = [];
                    }
                    
                    dataDestination = dataDestination[thisTime];
                }
            }
            
            dataDestination.push(lineValues);	
        }		
    };

    this.getColorForValue = function(thisValue, minValue, maxValue, valueScale)
    {	
        var normalizedValue = ((thisValue-minValue)*valueScale); 
        normalizedValue = Math.min(normalizedValue, 1.0);
        normalizedValue = Math.max(normalizedValue, 0.0);
        
        var fractionalIndex = (normalizedValue*(this._colorGradient.length-1));
        
        var lowerIndex = Math.floor(fractionalIndex);
        var higherIndex = Math.ceil(fractionalIndex);
        var lerpValue = (fractionalIndex-lowerIndex);
        var oneMinusLerp = (1.0-lerpValue);
        
        var lowerValue = this._colorGradient[lowerIndex];
        var higherValue = this._colorGradient[higherIndex];
        
        var alpha = ((lowerValue.alpha*oneMinusLerp)+(higherValue.alpha*lerpValue));
        var red = ((lowerValue.red*oneMinusLerp)+(higherValue.red*lerpValue));
        var green = ((lowerValue.green*oneMinusLerp)+(higherValue.green*lerpValue));
        var blue = ((lowerValue.blue*oneMinusLerp)+(higherValue.blue*lerpValue));
        
        var setColor = ((alpha<<24)|(red<<16)|(green<<8)|(blue<<0));
        
        return setColor;
    };

    this.getValuePointsNearLatLon = function(lat, lon, radius)
    {
        if (radius==0)
        {
            if (this._settings.is_point_blob_radius_in_pixels)
            {
                var pixelsPerDegreeLatitude = this.getPixelsPerDegreeLatitude();
                radius = (this._settings.point_blob_radius/pixelsPerDegreeLatitude);
            }
            else
            {
                radius = this._settings.point_blob_radius;
            }
        }
        
        var radiusSquared = (radius*radius);

        var currentValues = this.getCurrentValues();
            
        var result = [];
        for (var valuesIndex in currentValues)
        {
            var values = currentValues[valuesIndex];
            
            var valueLat = values[this._latitudeColumnIndex];
            var valueLon = values[this._longitudeColumnIndex];
            
            var deltaLat = (valueLat-lat);
            var deltaLon = (valueLon-lon);
            
            var distanceSquared = ((deltaLat*deltaLat)+(deltaLon*deltaLon));
            
            if (distanceSquared<radiusSquared)
            {
                var output = {};
                for(var headerIndex = 0; headerIndex < this._valueHeaders.length; headerIndex++ )
                {
                    var header = this._valueHeaders[headerIndex];

                    output[header] = values[headerIndex];
                }
                
                result.push(output);
            }
        
        }
        
        return result;
    };

    this.setSetting = function(key, value)
    {
        if (!this._settings.hasOwnProperty(key))
        {
            this.logError('Unknown key in setSetting('+key+')');
            return;
        }

        if (typeof this._settings[key] === "boolean")
        {	
            if (typeof value === 'string')
            {
                value = (value==='true');
            }
                
            this._settings[key] = (Boolean)(value);
        }
        else
        {
            this._settings[key] = value;
        }
            
        var changeHandlers =
        {
            'title_text': function(instance) {
                instance._title.setText(instance._settings.title_text);
                if (instance._settings.title_text!=='')
                    instance._title._y = 0;
                else
                    instance._title._y = -1000;
            },
            'time_range_start': function(instance) {
                instance.calculateFrameTimes();
                instance.updateTimelineDisplay();
            },
            'time_range_end': function(instance) {
                instance.calculateFrameTimes();
                instance.updateTimelineDisplay();
            },
            'point_blob_radius': function(instance) {
                instance._valuesDirty = true;
                instance._dirty = true;
            },
            'point_blob_value': function(instance) {
                instance._valuesDirty = true;
                instance._dirty = true;
            },
            'gradient_value_min': function(instance) {
                instance._settings.is_gradient_value_range_set =
                    ((instance._settings.gradient_value_min!=0)||
                    (instance._settings.gradient_value_max!=0));
                instance._valuesDirty = true;
                instance._dirty = true;
            },
            'gradient_value_max': function(instance) {
                instance._settings.is_gradient_value_range_set =
                    ((instance._settings.gradient_value_min!=0)||
                    (instance._settings.gradient_value_max!=0));
                instance._valuesDirty = true;
                instance._dirty = true;
            },
            'ocean_color': function(instance) {
                if (typeof instance._settings.ocean_color === 'string')
                {
                    instance._settings.ocean_color = instance._settings.ocean_color.replace('#', '0x');
                    instance._settings.ocean_color = (Number)(instance._settings.ocean_color);
                }
            },
            'title_background_color': function(instance) {
                if (typeof instance._settings.title_background_color === 'string')
                {
                    instance._settings.title_background_color = instance._settings.title_background_color.replace('#', '0x');
                    instance._settings.title_background_color = (Number)(instance._settings.title_background_color);
                }
                instance._title._backgroundColor = instance.colorStringFromNumber(instance._settings.title_background_color);
            },
            'show_map_tiles': function(instance) {
                if (typeof instance._settings.show_map_tiles==='string')
                    instance._settings.show_map_tiles = (Boolean)(instance._settings.show_map_tiles);
                instance._mapTilesDirty = instance._settings.show_map_tiles;
            },
            'information_alpha': function(instance) {
                instance.setWayDefault('alpha', instance._settings.information_alpha);
            },
            'credit_text': function(instance) {
                if (instance._credit !== null)
                {
                    // Workaround hack for a bad default setting
                    if (instance._settings.credit_text!='Created with <a href="http://openheatmap.com"><u>OpenHeatMap</u></a>')
                    {
                        instance._credit._text = instance._settings.credit_text;
                    }
                }
            }
        }
        
        if (changeHandlers.hasOwnProperty(key))
            changeHandlers[key](this);
    };

    this.repositionMoveableElements = function()
    {
        if (this._credit !== null)
        {
            this._credit._x = (this._settings.width-80);
            this._credit._y = (this._settings.height-20);
        }
            
        if (this._title !== null)
        {
            this._title._backgroundWidth = this._settings.width;
            this._title._x = 0;
        }

        if (this._timelineSlider !== null)
        {
            this._timelineSlider._y = (this._settings.height-30);
            this._timelineText._y = (this._settings.height-25);
            this._timelineButton._y = (this._settings.height-45);
        }
    };

    this.getLatLonViewingArea = function()
    {
        var topLeftScreen = new Point(0, 0);
        var bottomRightScreen = new Point(this._settings.width, this._settings.height);
            
        var topLeftLatLon = this.getLatLonFromXY(topLeftScreen, this._xYToLatLonMatrix);
        var bottomRightLatLon = this.getLatLonFromXY(bottomRightScreen, this._xYToLatLonMatrix);

        var result = {
            topLat: topLeftLatLon.lat,
            leftLon: topLeftLatLon.lon,
            bottomLat: bottomRightLatLon.lat,
            rightLon: bottomRightLatLon.lon
        };
        
        return result;
    };

    this.removeAllInlays = function()
    {
        this._inlays	= [];
        
        this._dirty = true;
    };

    this.removeAllWays = function()
    {
        this._ways = {};
        this._nodes = {};

        this._tagMap = {};
        this._lastSetWayIds = {};
        
        this._wayLayers = [];
        
        this._dirty = true;
    };

    this.getAllInlays = function()
    {
        var result = [];
        
        for (var inlayIndex=0; inlayIndex<this._inlays.length; inlayIndex+=1)
        {
            var inlay = this._inlays[inlayIndex];
        
            var topLeftScreen = this.getXYFromLatLon(inlay.worldTopLeftLatLon, this._latLonToXYMatrix);
            var bottomRightScreen = this.getXYFromLatLon(inlay.worldBottomRightLatLon, this._latLonToXYMatrix);
            
            var outputInlay =
            {
                left_x: topLeftScreen.x,
                top_y: topLeftScreen.y,
                right_x: bottomRightScreen.x,
                bottom_y: bottomRightScreen.y,
                top_lat: inlay.topLat,
                left_lon: inlay.leftLon,
                bottom_lat: inlay.bottomLat,
                right_lon: inlay.rightLon
            };

            result.push(outputInlay);
        }
        
        return result;
    };

    this.addPopup = function(lat, lon, text)
    {
        var popup =
        {
            originLatLon: { lat: lat, lon: lon },
            text: text
        };

        var width = 100;
        var height = 18;

        var screenPos = this.getXYFromLatLon(popup.originLatLon, this._latLonToXYMatrix);

        popup.uiComponent = new UIText(
            text,
            '16px Baskerville, Times New Roman, Serif',
            (screenPos.x-width), (screenPos.y-height),
            null,
            'center');

        popup.uiComponent.setBackground(width, height, '#ffffff');

        this.addChild(popup.uiComponent);
        
        this._popups.push(popup);
    };

    this.removeAllPopups = function()
    {
        for (var popupIndex=0; popupIndex<this._popups.length; popupIndex+=1)
        {
            var popup = this._popups[popupIndex];
            this.removeChild(popup.uiComponent);	
        }
        
        this._popups = [];
    }

    this.createURLForTile = function(latIndex, lonIndex, zoomIndex)
    {
        var result = this._settings.map_server_root;
        result += zoomIndex;
        result += '/';
        result += lonIndex;
        result += '/';
        result += latIndex;
        result += '.png';

        return result;	
    };

    this.drawMapTiles = function(canvas, width, height, latLonToXYMatrix, xYToLatLonMatrix)
    {
        var viewingArea = this.calculateViewingArea(width, height, xYToLatLonMatrix);
        
        var wantedTiles = this.prepareMapTiles(viewingArea, latLonToXYMatrix, xYToLatLonMatrix, width, height);

        var areAllLoaded = true;

        for (var currentURLIndex=0; currentURLIndex<wantedTiles.length; currentURLIndex+=1)
        {
            var currentURL = wantedTiles[currentURLIndex];
            if (!this._mapTiles[currentURL].imageLoader._isLoaded)
                areAllLoaded = false;
        }

        var mapTilesURLs = [];
        if (areAllLoaded)
        {
            mapTilesURLs = wantedTiles;
        }
        else
        {
            for (currentURL in this._mapTiles)
            {
                mapTilesURLs.push(currentURL);
            }
        }

        for (currentURLIndex=0; currentURLIndex<mapTilesURLs.length; currentURLIndex+=1)
        {
            var currentURL = mapTilesURLs[currentURLIndex];
            
            var tile = this._mapTiles[currentURL];

            if (!viewingArea.intersects(tile.boundingBox))
                continue;

            if (!tile.imageLoader._isLoaded)
                continue;
            
            var screenTopLeft = this.getXYFromLatLon(tile.topLeftLatLon, latLonToXYMatrix);
            var screenBottomRight = this.getXYFromLatLon(tile.bottomRightLatLon, latLonToXYMatrix);
            
            var screenLeft = screenTopLeft.x;
            var screenTop = screenTopLeft.y;
        
            var screenWidth = (screenBottomRight.x-screenTopLeft.x);
            var screenHeight = (screenBottomRight.y-screenTopLeft.y);

            this.drawImage(canvas, tile.imageLoader._image, screenLeft, screenTop, screenWidth, screenHeight);
        }
    };

    this.getTileIndicesFromLatLon = function(lat, lon, zoomLevel)
    {
        var mercatorLatitudeOrigin = this.latitudeToMercatorLatitude(this._settings.map_tile_origin_lat);
        var mercatorLatitudeHeight = this.latitudeToMercatorLatitude(this._settings.world_lat_height+this._settings.map_tile_origin_lat)-mercatorLatitudeOrigin;
        
        var zoomTileCount = (1<<zoomLevel);
        var zoomPixelsPerDegreeLatitude = ((this._settings.map_tile_height/mercatorLatitudeHeight)*zoomTileCount);
        var zoomPixelsPerDegreeLongitude = ((this._settings.map_tile_width/this._settings.world_lon_width)*zoomTileCount);

        var tileWidthInDegrees = (this._settings.map_tile_width/zoomPixelsPerDegreeLongitude);
        var tileHeightInDegrees = (this._settings.map_tile_height/zoomPixelsPerDegreeLatitude);

        var latIndex = ((this.latitudeToMercatorLatitude(lat)-mercatorLatitudeOrigin)/tileHeightInDegrees);
        latIndex = Math.max(latIndex, 0);
        latIndex = Math.min(latIndex, (zoomTileCount-1));
        
        var lonIndex = ((lon-this._settings.map_tile_origin_lon)/tileWidthInDegrees);
        lonIndex = Math.max(lonIndex, 0);
        lonIndex = Math.min(lonIndex, (zoomTileCount-1));
        
        var result = {
            latIndex: latIndex,
            lonIndex: lonIndex
        };
        
        return result;
    };

    this.getLatLonFromTileIndices = function(latIndex, lonIndex, zoomLevel)
    {
        var mercatorLatitudeOrigin = this.latitudeToMercatorLatitude(this._settings.map_tile_origin_lat);
        var mercatorLatitudeHeight = this.latitudeToMercatorLatitude(this._settings.world_lat_height+this._settings.map_tile_origin_lat)-mercatorLatitudeOrigin;
        
        var zoomTileCount = (1<<zoomLevel);
        var zoomPixelsPerDegreeLatitude = ((this._settings.map_tile_height/mercatorLatitudeHeight)*zoomTileCount);
        var zoomPixelsPerDegreeLongitude = ((this._settings.map_tile_width/this._settings.world_lon_width)*zoomTileCount);

        var tileWidthInDegrees = (this._settings.map_tile_width/zoomPixelsPerDegreeLongitude);
        var tileHeightInDegrees = (this._settings.map_tile_height/zoomPixelsPerDegreeLatitude);

        var lat = ((latIndex*tileHeightInDegrees)+mercatorLatitudeOrigin);
        var lon = ((lonIndex*tileWidthInDegrees)+this._settings.map_tile_origin_lon);
        
        var result = {
            lat: this.mercatorLatitudeToLatitude(lat),
            lon: lon
        };
        
        return result;
    };

    this.prepareMapTiles = function(viewingArea, latLonToXYMatrix, xYToLatLonMatrix, width, height)
    {	
        var pixelsPerDegreeLatitude = latLonToXYMatrix.d;
        
        var zoomPixelsPerDegreeLatitude = (this._settings.map_tile_height/this._settings.world_lat_height);
        var zoomLevel = 0;
        while (Math.abs(zoomPixelsPerDegreeLatitude*this._settings.map_tile_match_factor)<Math.abs(pixelsPerDegreeLatitude))
        {
            zoomLevel += 1;
            zoomPixelsPerDegreeLatitude *= 2;	
        }

        var zoomTileCount = (1<<zoomLevel);
        var zoomPixelsPerDegreeLongitude = ((this._settings.map_tile_width/this._settings.world_lon_width)*zoomTileCount);
        
        var tileWidthInDegrees = (this._settings.map_tile_width/zoomPixelsPerDegreeLongitude);
        var tileHeightInDegrees = (this._settings.map_tile_height/zoomPixelsPerDegreeLatitude);

        var start = this.getTileIndicesFromLatLon(viewingArea.bottom(), viewingArea.left(), zoomLevel);
        start.latIndex = Math.floor(start.latIndex);
        start.lonIndex = Math.floor(start.lonIndex);

        var end = this.getTileIndicesFromLatLon(viewingArea.top(), viewingArea.right(), zoomLevel);
        end.latIndex = Math.ceil(end.latIndex);
        end.lonIndex = Math.ceil(end.lonIndex);

        var wantedTiles = [];

        for (var latIndex = start.latIndex; latIndex<=end.latIndex; latIndex+=1)
        {
            for (var lonIndex = start.lonIndex; lonIndex<=end.lonIndex; lonIndex+=1)
            {
                var wantedTile = {};
            
                wantedTile.latIndex = latIndex;
                wantedTile.lonIndex = lonIndex;
                wantedTile.zoomIndex = zoomLevel;
                
                wantedTile.topLeftLatLon = this.getLatLonFromTileIndices(latIndex, lonIndex, zoomLevel);
                wantedTile.bottomRightLatLon = this.getLatLonFromTileIndices((latIndex+1), (lonIndex+1), zoomLevel);

                wantedTile.boundingBox = new Rectangle();			
                wantedTile.boundingBox = this.enlargeBoxToContain(wantedTile.boundingBox, new Point(wantedTile.topLeftLatLon.lon, wantedTile.topLeftLatLon.lat));
                wantedTile.boundingBox = this.enlargeBoxToContain(wantedTile.boundingBox, new Point(wantedTile.bottomRightLatLon.lon, wantedTile.bottomRightLatLon.lat));	
            
                wantedTiles.push(wantedTile);
            }
        }
        
        var result = [];
        
        for (var wantedTileIndex=0; wantedTileIndex<wantedTiles.length; wantedTileIndex+=1)
        {
            var wantedTile = wantedTiles[wantedTileIndex];
            
            var wantedURL = this.createURLForTile(wantedTile.latIndex, wantedTile.lonIndex, wantedTile.zoomIndex);
            
            if (!this._mapTiles.hasOwnProperty(wantedURL))
            {
                this._mapTiles[wantedURL] = {};
                
                this._mapTiles[wantedURL].imageLoader = new ExternalImageView(wantedURL, this._settings.map_tile_width, this._settings.map_tile_height, this);
                
                this._mapTiles[wantedURL].topLeftLatLon = wantedTile.topLeftLatLon;
                this._mapTiles[wantedURL].bottomRightLatLon = wantedTile.bottomRightLatLon;
                this._mapTiles[wantedURL].boundingBox = wantedTile.boundingBox;
            }
            
            this._mapTiles[wantedURL].isUsedThisFrame = true;
            
            result.push(wantedURL);
        }
        
        return result;
    }

    this.mercatorLatitudeToLatitude = function(mercatorLatitude) {
        var result = (180/Math.PI) * (2 * Math.atan(Math.exp((mercatorLatitude*2)*Math.PI/180)) - Math.PI/2);
	
        return result;
    };

    this.latitudeToMercatorLatitude = function(latitude) { 
        var result = (180/Math.PI) * Math.log(Math.tan(Math.PI/4+latitude*(Math.PI/180)/2));
	
        return (result/2);
    };

    this.calculateViewingArea = function(width, height, xYToLatLonMatrix)
    {
        var viewingArea = new Rectangle();
        
        var topLeftScreen = new Point(0, 0);
        var bottomRightScreen = new Point(width, height);
            
        var topLeftLatLon = this.getLatLonFromXY(topLeftScreen, xYToLatLonMatrix);
        var bottomRightLatLon = this.getLatLonFromXY(bottomRightScreen, xYToLatLonMatrix);
        
        viewingArea = this.enlargeBoxToContain(viewingArea, new Point(topLeftLatLon.lon, topLeftLatLon.lat));
        viewingArea = this.enlargeBoxToContain(viewingArea, new Point(bottomRightLatLon.lon, bottomRightLatLon.lat));	

        return viewingArea;	
    };

    this.trackMapTilesUsage = function()
    {
        for (var currentURL in this._mapTiles)
        {
            this._mapTiles[currentURL].isUsedThisFrame = false;	
        }	
    };

    this.deleteUnusedMapTiles = function()
    {
        var areAllLoaded = true;

        for (var currentURL in this._mapTiles)
        {
            if (this._mapTiles[currentURL].isUsedThisFrame&&
                !this._mapTiles[currentURL].imageLoader._isLoaded)
                areAllLoaded = false;
        }

        this._mapTilesDirty = false;
        
        if (areAllLoaded)
        {
            for (var currentURL in this._mapTiles)
            {
                if (!this._mapTiles[currentURL].isUsedThisFrame)
                {
                    this._mapTiles[currentURL].imageLoader = null;
                    delete this._mapTiles[currentURL];
                    this._mapTilesDirty = true;
                }	
            }
        }			
    };

    this.getValueHeaders = function()
    {
        return this._valueHeaders;	
    };

    this.addPopupAtScreenPosition = function(x, y, text)
    {
        var latLon = this.getLatLonFromXY(new Point(x, y), this._xYToLatLonMatrix);
        
        this.addPopup(latLon.lat, latLon.lon, text);	
    };

    this.getCurrentValues = function()
    {
        var currentValues = this._valueData;	

        if (this._hasTabs)
        {
            var currentTab = this._tabNames[this._selectedTabIndex];
            currentValues = currentValues[currentTab];
        }
        
        if (this._hasTime)
        {
            var currentTime = this._frameTimes[this._frameIndex];
            currentValues = currentValues[currentTime];
        }

        return currentValues;
    };

    this.drawTabsIntoViewer = function()
    {
        var tabCount = this._tabNames.length;
            
        var tabHeight = this._settings.tab_height;
        
        var tabTopY;
        if (this._settings.title_text!=='')
            tabTopY = (this._settings.title_size*1.5);
        else
            tabTopY = 0;
        
        var tabBottomY = (tabTopY+tabHeight);
        
        var context = this.beginDrawing(this._canvas);

        context.font = '9px Baskerville, Times New Roman, Serif';
        context.textBaseline = 'top';
        
        var tabLeftX = 0;
        
        for (var tabIndex = 0; tabIndex<tabCount; tabIndex+=1)
        {
            var isLast = (tabIndex==(tabCount-1));
            var isSelected = (tabIndex===this._selectedTabIndex);
            var isHovered = (tabIndex===this._hoveredTabIndex);

            var tabName = this._tabNames[tabIndex];
            var tabInfo = this._tabInfo[tabName];
            
            var metrics = context.measureText(tabName);
            var tabWidth = (metrics.width+5);
            
            var tabRightX = (tabLeftX+tabWidth);
            var distanceFromEdge = (this._settings.width-tabRightX);
            var addExtraTab = (isLast&&(distanceFromEdge>50));
            
            if (isLast&&!addExtraTab)
            {
                tabRightX = (this._settings.width-1);
                tabWidth = (tabRightX-tabLeftX);
            }

            tabInfo.leftX = tabLeftX;
            tabInfo.rightX = tabRightX;
            tabInfo.topY = tabTopY;
            tabInfo.bottomY = tabBottomY;
            
            if (tabWidth<1)
                continue;
            
            var fillColor;
            if (isSelected)
                fillColor = this._settings.title_background_color;
            else if (isHovered)
                fillColor = this.scaleColorBrightness(this._settings.title_background_color, 0.95);
            else
                fillColor = this.scaleColorBrightness(this._settings.title_background_color, 0.9);

            context.fillStyle = this.colorStringFromNumber(fillColor);
            context.beginPath()
            context.moveTo(tabLeftX, tabTopY);
            context.lineTo(tabRightX, tabTopY);
            context.lineTo(tabRightX, tabBottomY);
            context.lineTo(tabLeftX, tabBottomY);
            context.lineTo(tabLeftX, tabTopY);            
            context.closePath();
            context.fill();

            context.fillStyle = '#000000';
            context.fillText(tabName, tabLeftX+2, tabTopY);

            context.strokeStyle = '#000000';

            context.beginPath();
            context.moveTo(tabLeftX, tabBottomY);
            context.lineTo(tabLeftX, tabTopY);
            context.lineTo(tabRightX, tabTopY);
            context.lineTo(tabRightX, tabBottomY);
            if (!isSelected)
                context.closePath();
            context.stroke();

            tabLeftX = tabRightX;

            if (addExtraTab)
            {
                tabRightX = (this._settings.width-1);
                
                fillColor = this.scaleColorBrightness(this._settings.title_background_color, 0.9);
                
                context.fillStyle = this.colorStringFromNumber(fillColor);
                context.beginPath()
                context.moveTo(tabLeftX, tabTopY);
                context.lineTo(tabRightX, tabTopY);
                context.lineTo(tabRightX, tabBottomY);
                context.lineTo(tabLeftX, tabBottomY);
                context.lineTo(tabLeftX, tabTopY);            
                context.closePath();
                context.fill();

                context.strokeStyle = '#000000';

                context.beginPath();
                context.moveTo(tabLeftX, tabBottomY);
                context.lineTo(tabLeftX, tabTopY);
                context.lineTo(tabRightX, tabTopY);
                context.lineTo(tabRightX, tabBottomY);
                context.closePath();
                context.stroke();
            }
            
        }
        
        context.strokeStyle = '#000000';
        
        context.beginPath();
        context.moveTo(0, tabBottomY);
        context.lineTo(0, (this._settings.height-1));
        context.lineTo((this._settings.width-1), (this._settings.height-1));
        context.lineTo((this._settings.width-1), tabBottomY);
        context.stroke();
        
        this.endDrawing(context);
    };

    this.scaleColorBrightness = function(colorNumber, scale)
    {
        var alpha = (colorNumber>>24)&0xff;
        var red = (colorNumber>>16)&0xff;
        var green = (colorNumber>>8)&0xff;
        var blue = (colorNumber>>0)&0xff;
        
        var resultAlpha = alpha; // We'll end up with 'illegal' premult color values, but this shouldn't be a proble for our uses
        var resultRed = Math.floor(red*scale);
        var resultGreen = Math.floor(green*scale);
        var resultBlue = Math.floor(blue*scale);
        
        resultRed = Math.max(0, resultRed);
        resultGreen = Math.max(0, resultGreen);
        resultBlue = Math.max(0, resultBlue);
            
        resultRed = Math.min(255, resultRed);
        resultGreen = Math.min(255, resultGreen);
        resultBlue = Math.min(255, resultBlue);
        
        var result =
            (resultAlpha<<24)|
            (resultRed<<16)|
            (resultGreen<<8)|
            (resultBlue<<0);
        
        return result;
    }

    this.isEventInTopBar = function(event)
    {
        var hasTitle = (this._settings.title_text!=='');
        
        if ((!hasTitle)&&(!this._hasTabs||!this._settings.show_tabs))
            return false;
        
        var tabHeight = this._settings.tab_height;
        
        var tabTopY;
        if (hasTitle)
            tabTopY = (this._settings.title_size*1.5);
        else
            tabTopY = 0;
        
        var tabBottomY = (tabTopY+tabHeight);
        
        var localPosition = this.getLocalPosition($(event.target), event.pageX, event.pageY);
        
        return (localPosition.y<tabBottomY);
    };

    this.onTopBarClick = function(event)
    {
        var tabIndex = this.getTabIndexFromEvent(event);
        
        if (tabIndex!==-1)
        {
            this._selectedTabIndex = tabIndex;
            this._valuesDirty = true;
            this._dirty = true;
        }
        
        return true;
    };
	
    this.onTopBarDoubleClick = function(event)
    {
        var tabIndex = this.getTabIndexFromEvent(event);
        
        if (tabIndex!==-1)
        {
            this._selectedTabIndex = tabIndex;
            this._valuesDirty = true;
            this._dirty = true;
        }
        
        return true;
    };
	
    this.onTopBarMouseDown = function(event)
    {	
        return true;	
    };

    this.onTopBarMouseUp = function(event)
    {	
        return true;		
    };

    this.onTopBarMouseOver = function(event)
    {
        return true;	
    };

    this.onTopBarMouseOut = function(event)
    {
        return true;	
    };
	
    this.onTopBarMouseMove = function(event)
    {
        var tabIndex = this.getTabIndexFromEvent(event);
        
        this._hoveredTabIndex = tabIndex;
        
        return true;	
    };
	
    this.getTabIndexFromEvent = function(event)
    {
        var localPosition = this.getLocalPosition($(event.target), event.pageX, event.pageY);

        var x = localPosition.x;
        var y = localPosition.y;
        
        for (var tabIndex = 0; tabIndex<this._tabNames.length; tabIndex+=1)
        {
            var tabName = this._tabNames[tabIndex];
            var tabInfo = this._tabInfo[tabName];
            
            if ((x>=tabInfo.leftX)&&
                (x<tabInfo.rightX)&&
                (y>=tabInfo.topY)&&
                (y<tabInfo.bottomY))
                return tabIndex;
        }
        
        return -1;
    };

    this.createPointsGrid = function(viewingArea, latLonToXYMatrix)
    {
        if (!this._hasPointValues)
            return;

        var blobRadius;
        if (this._settings.is_point_blob_radius_in_pixels)
        {	
            var pixelsPerDegreeLatitude = latLonToXYMatrix.d;
            blobRadius = Math.abs(this._settings.point_blob_radius/pixelsPerDegreeLatitude);
        }
        else
        {
            blobRadius = this._settings.point_blob_radius;	
        }
        var twoBlobRadius = (2*blobRadius);
        var pointBlobValue = this._settings.point_blob_value;

        this._pointsGrid = new BucketGrid(viewingArea, 64, 64);
        
        var currentValues = this.getCurrentValues();
        
        var hasValues = (this._valueColumnIndex!==-1);
        
        var index = 0;
        for (var valuesIndex in currentValues)
        {
            var values = currentValues[valuesIndex];
            
            var lat = values[this._latitudeColumnIndex];
            var lon = values[this._longitudeColumnIndex];
            var pointValue;
            if (hasValues)
                pointValue = values[this._valueColumnIndex];
            else
                pointValue = pointBlobValue;
            
            var boundingBox = new Rectangle(lon-blobRadius, lat-blobRadius, twoBlobRadius, twoBlobRadius);
            
            if (!viewingArea.intersects(boundingBox))
                continue;
            
            var latLon = { 
                pos: new Point(lon, lat),
                index: index,
                value: pointValue
            };
            
            this._pointsGrid.insertObjectAt(boundingBox, latLon);
            
            index += 1;
        }		
    };

    this.drawPointBlobTile = function(width, 
        height, 
        viewingArea, 
        latLonToXYMatrix, 
        xYToLatLonMatrix, 
        leftX,
        topY,
        tileWidth, 
        tileHeight)
    {
        var bitmapWidth = this._pointBlobBitmapWidth;
        var bitmapHeight = this._pointBlobBitmapHeight;
        
        var rightX = (leftX+tileWidth);
        var bottomY = (topY+tileHeight);
        
        var blobRadius;
        if (this._settings.is_point_blob_radius_in_pixels)
        {	
            var pixelsPerDegreeLatitude = latLonToXYMatrix.d;
            blobRadius = Math.abs(this._settings.point_blob_radius/pixelsPerDegreeLatitude);
        }
        else
        {
            blobRadius = this._settings.point_blob_radius;	
        }
        var twoBlobRadius = (2*blobRadius);
        var blobRadiusSquared = (blobRadius*blobRadius);
        
        if (this._settings.is_gradient_value_range_set)
        {
            var minValue = this._settings.gradient_value_min;
            var maxValue = this._settings.gradient_value_max;	
            if (Math.abs(maxValue-minValue)<0.00001)	
                minValue = (maxValue-1.0);
        }
        else
        {
            minValue = 0;
            maxValue = 1.0;
        }
        var valueScale = (1/(maxValue-minValue));
        
        var hasValues = (this._valueColumnIndex!==-1);
        
        var isValueDistance = (this._settings.is_value_distance);
        
        var leftLon = viewingArea.left();
        var rightLon = viewingArea.right();
        var widthLon = (rightLon-leftLon);
        var stepLon = (widthLon/bitmapWidth);
        
        var topLat = viewingArea.bottom();
        var bottomLat = viewingArea.top();
        
        var topLatMercator = this.latitudeToMercatorLatitude(topLat);
        var bottomLatMercator = this.latitudeToMercatorLatitude(bottomLat);
        var heightLat = (bottomLatMercator-topLatMercator);
        var stepLat = (heightLat/bitmapHeight);
        
        var context = this.beginDrawing(this._pointBlobCanvas);
        var imageData = context.createImageData(tileWidth, tileHeight);
        
        var pixelData = imageData.data;
        var pixelDataIndex = 0;
        
        var zeroColor = 0x00000000;
        var fullColor = this.getColorForValue(maxValue, minValue, maxValue, valueScale);
        
        var worldPoint = new Point();
        for (var bitmapY = topY; bitmapY<bottomY; bitmapY+=1)
        {
            worldPoint.y = this.mercatorLatitudeToLatitude(topLatMercator+(stepLat*bitmapY));
            for (var bitmapX = leftX; bitmapX<rightX; bitmapX+=1)
            {			
                worldPoint.x = (leftLon+(stepLon*bitmapX));
                
                var candidatePoints = this._pointsGrid.getContentsAtPoint(worldPoint);
                
                if (candidatePoints.length<1)
                {
                    this.writePixel(pixelData, pixelDataIndex, zeroColor);
                    pixelDataIndex += 4;
                    continue;
                }
                
                var value = 0;
                var lerpTotal = 0;
                var minDistance = blobRadius;
                
                for (var pointIndex in candidatePoints)
                {
                    var point = candidatePoints[pointIndex];
                    
                    var pos = point.pos;
                    var delta = worldPoint.subtract(pos);
                    var distanceSquared = ((delta.x*delta.x)+(delta.y*delta.y));
                    if (distanceSquared>blobRadiusSquared)
                        continue;
                    
                    var distance = Math.sqrt(distanceSquared);
                    var lerp = (1-(distance/blobRadius));
                    
                    value += (point.value*lerp);
                    lerpTotal += lerp;
                    minDistance = Math.min(minDistance, distance);
                }
                
                if (isValueDistance)
                {
                    value = (minValue+((1-(minDistance/blobRadius))*valueScale));                           
                }
                else if (lerpTotal>0)
                {
                    if (hasValues)
                        value = (value/lerpTotal);	
                }
                else
                {
                    value = 0;
                }
                
                var alpha = Math.floor(255*(Math.min(lerpTotal, 1.0)));
                
                var color = this.getColorForValue(value, minValue, maxValue, valueScale);
                
                var colorAlpha = (color>>24)&0xff;
                var outputAlpha = ((colorAlpha*alpha)>>8)&0xff;
                
                color = (color&0x00ffffff)|(outputAlpha<<24);

                this.writePixel(pixelData, pixelDataIndex, color);
                pixelDataIndex += 4;
            }	
        }

        context.putImageData(imageData, leftX, topY);
        
        this.endDrawing(context);
    };

    this.setAnimationTime = function(time) {
        for (var index in this._frameTimes)
        {
            if (this._frameTimes[index] === time)
            {
                this._frameIndex = (Number)(index);
                this.updateTimelineDisplay();
                break;
            }

        }       
    };

    this.getAnimationTime = function() {
        if (!this._hasTime)
            return null;
	
        var currentTime = this._frameTimes[this._frameIndex];
        return currentTime;	
    };

    this.getTabInfo = function() {
        if (!this._hasTabs)
            return null;
	
        var result = {
            'selected_tab_index': this._selectedTabIndex,
            'tab_names': this._tabNames
        };
        
        return result;
    };
	
    this.selectTab = function(tabIndex) {
        this._selectedTabIndex = tabIndex;
        this._valuesDirty = true;
        this._dirty = true;
    };

    this.drawBackgroundBitmap = function(width, height, viewingArea, latLonToXYMatrix, xYToLatLonMatrix) {
        if (!this._hasPointValues)
            return null;
	
        if ((this._redrawCountdown>0)&&(!this._dirty))
            return null;

        var result = null;
	
        var pointDrawingShape = this._settings.point_drawing_shape;
        if ((pointDrawingShape=='blob')||(this._settings.is_value_distance))
            result = this.drawPointBlobBitmap(width, height, viewingArea, latLonToXYMatrix, xYToLatLonMatrix);
        else if (pointDrawingShape=='circle')
            result = this.drawPointCircleBitmap(width, height, viewingArea, latLonToXYMatrix, xYToLatLonMatrix);
        else
            logError('Unknown type in setting point_drawing_shape: "'+pointDrawingShape+'"');

        return result;
    };

    this.drawPointCircleBitmap = function(width, height, viewingArea, latLonToXYMatrix, xYToLatLonMatrix) {
        var pixelsPerDegreeLatitude = latLonToXYMatrix.d;
        var blobRadius;
        if (this._settings.is_point_blob_radius_in_pixels)
        {	
            blobRadius = Math.abs(this._settings.point_blob_radius/pixelsPerDegreeLatitude);
        }
        else
        {
            blobRadius = this._settings.point_blob_radius;	
        }
        var twoBlobRadius = (2*blobRadius);
        var pointBlobValue = this._settings.point_blob_value;
        var radiusInPixels = Math.abs(blobRadius*pixelsPerDegreeLatitude);
        
        if (this._settings.is_gradient_value_range_set)
        {
            var minValue = this._settings.gradient_value_min;
            var maxValue = this._settings.gradient_value_max;	
        }
        else
        {
            minValue = this._smallestValue;
            maxValue = this._largestValue;
        }
        if (Math.abs(maxValue-minValue)<0.00001)	
            minValue = (maxValue-1.0);
        var valueScale = (1/(maxValue-minValue));	
        
        var currentValues = this.getCurrentValues();
        
        var hasValues = (this._valueColumnIndex!==-1);

        var foundPoints = [];	
        for (var index = 0; index<currentValues.length; index+=1)
        {
            values = currentValues[index];
            var lat = values[this._latitudeColumnIndex];
            var lon = values[this._longitudeColumnIndex];
            var pointValue;
            if (hasValues)
                pointValue = values[this._valueColumnIndex];
            else
                pointValue = pointBlobValue;
            
            var boundingBox = new Rectangle(lon-blobRadius, lat-blobRadius, twoBlobRadius, twoBlobRadius);

            if (!viewingArea.intersects(boundingBox))
                continue;
        
            if (isNaN(lat)||isNaN(lon)||isNaN(pointValue))
                continue;
        
            foundPoints.push({
                    "lat": lat,
                    "lon": lon,
                    "value": pointValue
            });
        }
            
        foundPoints.sort(function (a, b) { return a.value-b.value; });	
        
        var intermediate = this.createCanvas(width, height);
        var context = this.beginDrawing(intermediate);

        var lineColor = Number(this._settings.circle_line_color)
        var lineAlpha = Number(this._settings.circle_line_alpha)
        var lineThickness = Number(this._settings.circle_line_thickness)

        for (var index = 0; index<foundPoints.length; index += 1)
        {
            var point = foundPoints[index];
            
            var center = this.getXYFromLatLon(point, latLonToXYMatrix);
            pointValue = point.value;
            
            var currentColorAndAlpha = this.getColorForValue(pointValue, minValue, maxValue, valueScale);
            var currentColor = (currentColorAndAlpha & 0x00ffffff);
            var currentAlpha = ((currentColorAndAlpha>>24) & 0xff)/255.0;

            var normalizedValue = (((pointValue-minValue)*valueScale));
            normalizedValue = Math.max(0.0, normalizedValue);
            
            var currentRadius = (Math.sqrt(normalizedValue)*radiusInPixels);
            
            currentRadius = Math.max(this._settings.circle_minimum_radius, currentRadius);

            if (lineAlpha<0.01)
            {
                context.lineWidth = 0;
            }
            else
            {
                context.lineWidth = 1.0;
                context.strokeStyle = this.colorStringFromNumber(lineColor, (lineAlpha*currentAlpha));
            }

            context.fillStyle = this.colorStringFromNumber(currentColor, currentAlpha);		
            
            context.beginPath();
            context.arc(center.x, center.y, currentRadius, 0, Math.PI*2, true);
            context.closePath();
            context.fill();
            if (lineAlpha>0.01)
                context.stroke();
        }		

        this.endDrawing(context);

        var result = this.createCanvas(width, height);
        context = this.beginDrawing(result);

        context.shadowColor = this.colorStringFromNumber(0x000000, 0.8);
        context.shadowOffsetX = 4.0*Math.sqrt(2.0);
        context.shadowOffsetY = 4.0*Math.sqrt(2.0);
        context.shadowBlur = 12.0;

        context.drawImage(intermediate.get(0), 0, 0, width, height);

        this.endDrawing(context);

        this._pointBlobStillRendering = false;

        return result;
    };

    this.beginDrawing = function(canvas) {
        if (!canvas)
            canvas = this._canvas;
            
        var context = canvas.get(0).getContext('2d');
        context.save();
        return context;
    };

    this.endDrawing = function(context) {
        context.restore();
    };
    
    this.getLocalPosition = function(element, pageX, pageY) {
        var elementPosition = element.elementLocation();

        var result = new Point(
            (pageX-elementPosition.x),
            (pageY-elementPosition.y)
        );

        return result;
    };

    this.clearCanvas = function(canvas) {
        var context = this.beginDrawing(canvas);
        
        context.clearRect(0, 0, this._settings.width, this._settings.height);
        
        this.endDrawing(context);
    };

    // From http://stackoverflow.com/questions/359788/javascript-function-name-as-a-string   
    this.externalInterfaceCall = function(functionName) {
        var args = Array.prototype.slice.call(arguments).splice(1);
        var namespaces = functionName.split(".");
        var func = namespaces.pop();
        var context = window;
        for(var i = 0; i < namespaces.length; i++) {
            context = context[namespaces[i]];
        }
        return context[func].apply(this, args);
    };
    
    this.createCanvas = function(width, height) {
        return $(
            '<canvas '
            +'width="'+width+'" '
            +'height="'+height+'"'
            +'"></canvas>'
        );
    };
    
    this.colorStringFromNumber = function(colorNumber, alpha)
    {
        var red = (colorNumber>>16)&0xff;
        var green = (colorNumber>>8)&0xff;
        var blue = (colorNumber>>0)&0xff;

        if (typeof alpha === 'undefined')
            alpha = 1.0;
            
        var result = 'rgba(';
        result += red;
        result += ',';
        result += green;
        result += ',';
        result += blue;
        result += ',';
        result += alpha;
        result += ')';
        
        return result;
    };
    
    this.drawImage = function(destination, source, x, y, w, h)
    {
        var context = this.beginDrawing(destination);
        context.drawImage(source, x, y, w, h);
        this.endDrawing(context);
    };

    this.fillRect = function(destination, x, y, width, height, color)
    {
        var context = this.beginDrawing(destination);
        context.fillStyle = this.colorStringFromNumber(color);
        context.fillRect(x, y, width, height);
        this.endDrawing(context);
    };
    
    this.writePixel = function(pixelData, index, color)
    {
        var alpha = ((color>>24)&0xff);
        var red = ((color>>16)&0xff);
        var green = ((color>>8)&0xff);
        var blue = ((color>>0)&0xff);
        
        pixelData[index+0] = red;
        pixelData[index+1] = green;
        pixelData[index+2] = blue;
        pixelData[index+3] = alpha;
    };
    
    this.addChild = function(element)
    {
        this._viewerElements.push(element);
    };

    this.drawViewerElements = function(canvas)
    {
        var context = this.beginDrawing(canvas);
        
        for (var elementIndex=0; elementIndex<this._viewerElements.length; elementIndex+=1)
        {
            var element = this._viewerElements[elementIndex];
            
            element.draw(context);
        }
        
        this.endDrawing(context);    
    };
    
    this.handleViewerElementEvent = function(event, callback)
    {
        var currentPosition = this.getLocalPosition($(event.target), event.pageX, event.pageY);
        event.localX = currentPosition.x;
        event.localY = currentPosition.y;

        for (var elementIndex=0; elementIndex<this._viewerElements.length; elementIndex+=1)
        {
            var element = this._viewerElements[elementIndex];
            if (typeof element[callback] === 'undefined')
                continue;
                
            var result = element[callback](event);
            if (!result)
                return false;
        }
    
        return true;
    };

    this.removeChild = function(elementToRemove)
    {
        var newElements = [];
        for (var elementIndex=0; elementIndex<this._viewerElements.length; elementIndex+=1)
        {
            var element = this._viewerElements[elementIndex];
            if (element!==elementToRemove)
                newElements.push(element);
        }
        
        this._viewerElements = newElements;
    };

    this.__constructor(canvas, width, height);

    return this;
}

function Matrix(a, b, c, d, tx, ty)
{
    if (typeof a === 'undefined')
    {
        a = 1; b = 0;
        c = 0; d = 1;
        tx = 0; ty = 0;
    }
    
    this.a = a;
    this.b = b;
    this.c = c;
    this.d = d;
    this.tx = tx;
    this.ty = ty;
    
    this.transformPoint = function (p) {
        var result = new Point(
            (p.x*this.a)+(p.y*this.c)+this.tx,
            (p.x*this.b)+(p.y*this.d)+this.ty
        );
    
        return result;
    };
    
    this.translate = function (x, y) {
        this.tx += x;
        this.ty += y;
        
        return this;
    };
    
    this.scale = function (x, y) {
    
        var scaleMatrix = new Matrix(x, 0, 0, y, 0, 0);
        this.concat(scaleMatrix);
        
        return this;
    };
    
    this.concat = function (m) {
    
        this.copy( new Matrix(
            (this.a*m.a)+(this.b*m.c), (this.a*m.b)+(this.b*m.d),
            (this.c*m.a)+(this.d*m.c), (this.c*m.b)+(this.d*m.d),
            (this.tx*m.a)+(this.ty*m.c)+m.tx, (this.tx*m.b)+(this.ty*m.d)+m.ty
        ));
        
        return this;
    };

    this.invert = function () {
    
        var adbc = ((this.a*this.d)-(this.b*this.c));
    
        this.copy(new Matrix(
            (this.d/adbc), (-this.b/adbc),
            (-this.c/adbc), (this.a/adbc),
            (((this.c*this.ty)-(this.d*this.tx))/adbc),
            -(((this.a*this.ty)-(this.b*this.tx))/adbc)
        ));
        
        return this;
    };

    this.clone = function () {
    
        var result = new Matrix(
            this.a, this.b,
            this.c, this.d,
            this.tx, this.ty
        );
        
        return result;
    };

    this.zoomAroundPoint = function (center, zoomFactor) {
        var translateToOrigin = new Matrix();
        translateToOrigin.translate(-center.x, -center.y);
        
        var scale = new Matrix();
        scale.scale(zoomFactor, zoomFactor);
        
        var translateFromOrigin = new Matrix();
        translateFromOrigin.translate(center.x, center.y);

        var zoom = new Matrix();
        zoom.concat(translateToOrigin);
        zoom.concat(scale);
        zoom.concat(translateFromOrigin);
        
        this.concat(zoom);
        return this;
    }
    
    this.copy = function(m) {
        this.a = m.a;
        this.b = m.b;
        this.c = m.c;
        this.d = m.d;
        this.tx = m.tx;
        this.ty = m.ty;
        
        return this;
    }
}

function Point(x, y)
{
    if (typeof x === 'undefined')
    {
        x = 0;
        y = 0;
    }
    
    this.x = (Number)(x);
    this.y = (Number)(y);
    
    this.add = function (p) {
        var result = new Point((this.x+p.x), (this.y+p.y));
        return result;
    };

    this.subtract = function (p) {
        var result = new Point((this.x-p.x), (this.y-p.y));
        return result;
    };
    
    this.dot = function (p) {
        var result = ((this.x*p.x)+(this.y*p.y));
        return result;
    };

    this.cross = function (p) {
        var result = ((this.x*p.y)-(this.y*p.x));
        return result;
    };
    
    this.clone = function () {
        return new Point(this.x, this.y);
    };

}

jQuery.fn.elementLocation = function() 
{
    var curleft = 0;
    var curtop = 0;

    var obj = this;

    do {
        curleft += obj.attr('offsetLeft');
        curtop += obj.attr('offsetTop');

        obj = obj.offsetParent();
    } while ( obj.attr('tagName') != 'BODY' );

    return ( {x:curleft, y:curtop} );
};

function Rectangle(x, y, width, height)
{
    if (typeof x==='undefined')
        x = 0;

    if (typeof y==='undefined')
        y = 0;
        
    if (typeof width==='undefined')
        width = 0;

    if (typeof height==='undefined')
        height = 0;

    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;

    this.bottom = function(newY) {
        if (typeof newY !== 'undefined')
            this.height = (newY-this.y);
        return (this.y+this.height);
    };
    
    this.bottomRight = function() {
        return new Point(this.right(), this.bottom());
    };

    this.left = function(newX) {
        if (typeof newX !== 'undefined')
        {
            this.width += (this.x-newX);
            this.x = newX;
        }
        return this.x;
    };
    
    this.right = function(newX) {
        if (typeof newX !== 'undefined')
            this.width = (newX-this.x);
        return (this.x+this.width);
    };
    
    this.size = function() {
        return new Point(this.width, this.height);
    };
    
    this.top = function(newY) {
        if (typeof newY !== 'undefined')
        {
            this.height += (this.y-newY);
            this.y = newY;
        }
        return this.y;
    };

    this.topLeft = function() {
        return new Point(this.x, this.y);
    };

    this.clone = function() {
        return new Rectangle(this.x, this.y, this.width, this,height);
    };
    
    this.contains = function(x, y) {
        var isInside = 
            (x>=this.x)&&
            (y>=this.y)&&
            (x<this.right())&&
            (y<this.bottom());
        return isInside;
    };
    
    this.containsPoint = function(point) {
        return this.contains(point.x, point.y);
    };
    
    this.containsRect = function(rect) {
        var isInside = 
            (rect.x>=this.x)&&
            (rect.y>=this.y)&&
            (rect.right()<=this.right())&&
            (rect.bottom()<=this.bottom());
        return isInside;    
    };
    
    this.equals = function(toCompare) {
        var isIdentical =
            (toCompare.x===this.x)&&
            (toCompare.y===this.y)&&
            (toCompare.width===this.width)&&
            (toCompare.height===this.height);
        return isIdentical;
    };
    
    this.inflate = function(dx, dy) {
        this.x -= dx;
        this.y -= dy;
        this.width += (2*dx);
        this.height += (2*dy);
    };
    
    this.inflatePoint = function(point) {
        this.inflate(point.x, point.y);
    };
    
    this.inclusiveRangeContains = function(value, min, max) {
        var isInside =
            (value>=min)&&
            (value<=max);
            
        return isInside;
    };
    
    this.intersectRange = function(aMin, aMax, bMin, bMax) {

        var maxMin = Math.max(aMin, bMin);
        if (!this.inclusiveRangeContains(maxMin, aMin, aMax)||
            !this.inclusiveRangeContains(maxMin, bMin, bMax))
            return null;
            
        var minMax = Math.min(aMax, bMax);
        
        if (!this.inclusiveRangeContains(minMax, aMin, aMax)||
            !this.inclusiveRangeContains(minMax, bMin, bMax))
            return null;
    
        return { min: maxMin, max: minMax };
    };
    
    this.intersection = function(toIntersect) {
        var xSpan = this.intersectRange(
            this.x, this.right(),
            toIntersect.x, toIntersect.right());
        
        if (!xSpan)
            return null;
            
        var ySpan = this.intersectRange(
            this.y, this.bottom(),
            toIntersect.y, toIntersect.bottom());
        
        if (!ySpan)
            return null;
            
        var result = new Rectangle(
            xSpan.min,
            ySpan.min,
            (xSpan.max-xSpan.min),
            (ySpan.max-ySpan.min));
        
        return result;
    };
    
    this.intersects = function(toIntersect) {
        var intersection = this.intersection(toIntersect);
        
        return (typeof intersection !== 'undefined');
    };
    
    this.isEmpty = function() {
        return ((this.width<=0)||(this.height<=0));
    };
    
    this.offset = function(dx, dy) {
        this.x += dx;
        this.y += dy;
    };
    
    this.offsetPoint = function(point) {
        this.offset(point.x, point.y);
    };
    
    this.setEmpty = function() {
        this.x = 0;
        this.y = 0;
        this.width = 0;
        this.height = 0;
    };
    
    this.toString = function() {
        var result = '{';
        result += '"x":'+this.x+',';
        result += '"y":'+this.y+',';
        result += '"width":'+this.width+',';
        result += '"height":'+this.height+'}';
        
        return result;
    };
    
    this.union = function(toUnion) {
        var minX = Math.min(toUnion.x, this.x);
        var maxX = Math.max(toUnion.right(), this.right());
        var minY = Math.min(toUnion.y, this.y);
        var maxY = Math.max(toUnion.bottom(), this.bottom());

        var result = new Rectangle(
            minX,
            minY,
            (maxX-minX),
            (maxY-minY));
        
        return result;
    };
    
    return this;
}

function BucketGrid(boundingBox, rows, columns)
{
    this.__constructor = function(boundingBox, rows, columns)
    {
        this._boundingBox = boundingBox;
        this._rows = rows;
        this._columns = columns;
        
        this._grid = [];
        
        this._originLeft = boundingBox.left();
        this._originTop = boundingBox.top();
        
        this._columnWidth = this._boundingBox.width/this._columns;
        this._rowHeight = this._boundingBox.height/this._rows;
        
        for (var rowIndex = 0; rowIndex<this._rows; rowIndex+=1)
        {
            this._grid[rowIndex] = [];
            
            var rowTop = (this._originTop+(this._rowHeight*rowIndex));
            
            for (var columnIndex = 0; columnIndex<this._columns; columnIndex+=1)
            {
                var columnLeft = (this._originLeft+(this._columnWidth*columnIndex));
                this._grid[rowIndex][columnIndex] = {
                    head_index: 0,
                    contents: { }
                };
            }
        }			

    };
    
    this.insertObjectAtPoint = function(point, object)
    {
        this.insertObjectAt(new Rectangle(point.x, point.y, 0, 0), object);
    }
    
    this.insertObjectAt = function(boundingBox, object)
    {
        var leftIndex = Math.floor((boundingBox.left()-this._originLeft)/this._columnWidth);
        var rightIndex = Math.floor((boundingBox.right()-this._originLeft)/this._columnWidth);
        var topIndex = Math.floor((boundingBox.top()-this._originTop)/this._rowHeight);
        var bottomIndex = Math.floor((boundingBox.bottom()-this._originTop)/this._rowHeight);

        leftIndex = Math.max(leftIndex, 0);
        rightIndex = Math.min(rightIndex, (this._columns-1));
        topIndex = Math.max(topIndex, 0);
        bottomIndex = Math.min(bottomIndex, (this._rows-1));

        for (var rowIndex = topIndex; rowIndex<=bottomIndex; rowIndex+=1)
        {
            for (var columnIndex = leftIndex; columnIndex<=rightIndex; columnIndex+=1)
            {
                var bucket = this._grid[rowIndex][columnIndex];
                bucket.contents[bucket.head_index] = object;
                bucket.head_index += 1;
            }
        }
        
    };

    this.removeObjectAt = function(boundingBox, object)
    {
        var leftIndex = Math.floor((boundingBox.left()-this._originLeft)/this._columnWidth);
        var rightIndex = Math.floor((boundingBox.right()-this._originLeft)/this._columnWidth);
        var topIndex = Math.floor((boundingBox.top()-this._originTop)/this._rowHeight);
        var bottomIndex = Math.floor((boundingBox.bottom()-this._originTop)/this._rowHeight);

        leftIndex = Math.max(leftIndex, 0);
        rightIndex = Math.min(rightIndex, (this._columns-1));
        topIndex = Math.max(topIndex, 0);
        bottomIndex = Math.min(bottomIndex, (this._rows-1));

        for (var rowIndex = topIndex; rowIndex<=bottomIndex; rowIndex+=1)
        {
            for (var columnIndex = leftIndex; columnIndex<=rightIndex; columnIndex+=1)
            {
                var bucket = this._grid[rowIndex][columnIndex];
                for (var index=0; index<bucket.contents.length; index+=1)
                {
                    if (bucket.contents[index]==object)
                    {
                        delete bucket.contents[index];
                        break;
                    }
                }
            }
        }
        
    };
    
    this.getContentsAtPoint = function(point)
    {
        return this.getContentsAt(new Rectangle(point.x, point.y, 0, 0));
    };
    
    this.getContentsAt = function(boundingBox)
    {
        var result = [];

        var leftIndex = Math.floor((boundingBox.left()-this._originLeft)/this._columnWidth);
        var rightIndex = Math.floor((boundingBox.right()-this._originLeft)/this._columnWidth);
        var topIndex = Math.floor((boundingBox.top()-this._originTop)/this._rowHeight);
        var bottomIndex = Math.floor((boundingBox.bottom()-this._originTop)/this._rowHeight);

        leftIndex = Math.max(leftIndex, 0);
        rightIndex = Math.min(rightIndex, (this._columns-1));
        topIndex = Math.max(topIndex, 0);
        bottomIndex = Math.min(bottomIndex, (this._rows-1));

        for (var rowIndex = topIndex; rowIndex<=bottomIndex; rowIndex+=1)
        {
            for (var columnIndex = leftIndex; columnIndex<=rightIndex; columnIndex+=1)
            { 
                var bucket = this._grid[rowIndex][columnIndex];
                for (var objectIndex in bucket.contents)
                    result.push(bucket.contents[objectIndex]);
            }
        }
        
        return result;
    };

    this.__constructor(boundingBox, rows, columns);
    
    return this;
}

function ExternalImageView(imagePath, width, height, myParent)
{
    this.__constructor = function(imagePath, width, height, myParent)
    {
        this._myParent = myParent;
		this._isLoaded = false;
        this._image = new Image();
        
        var instance = this;
        this._image.onload = function() { instance.onComplete(); };
        this._image.src = imagePath;
    };

    this.onComplete = function() 
    {
        this._isLoaded = true;
        
        // I know, I know, I should really be sending up an event or something less hacky
        this._myParent._mapTilesDirty = true;
    };
    
    this.__constructor(imagePath, width, height, myParent);
}

function UIImage(imagePath, x, y)
{
    this.__constructor = function(imagePath, x, y)
    {
        this._x = x;
        this._y = y;
        this._isVisible = true;
    
		this._isLoaded = false;
        this._image = new Image();
        
        var instance = this;
        this._image.onload = function() { instance.onComplete(); };
        this._image.src = imagePath;
    };

    this.onComplete = function() 
    {
        this._isLoaded = true;
        this._width = this._image.width;
        this._height = this._image.height;
    };
    
    this.draw = function(context)
    {
        if (!this._isLoaded || !this._isVisible)
            return;
            
        context.drawImage(this._image, this._x, this._y);    
    };
    
    this.__constructor(imagePath, x, y);
}

function Slider(x, y, width, height, changeCallback)
{
    this.__constructor = function(x, y, width, height, changeCallback)
    {
        this._isVertical = (width<height);

        this._x = x;
        this._y = y;
        this._width = width;
        this._height = height;
        this._isVisible = true;
        
        this._value = 0;

        this._trackBreadth = 6;
        this._capLength = 3;

        if (this._isVertical)
        {
            this._trackStart = new UIImage('http://static.openheatmap.com/images/vtrack.png', 0, 0);
            this._trackMid = new UIImage('http://static.openheatmap.com/images/vtrack.png', 0, 0);
            this._trackEnd = new UIImage('http://static.openheatmap.com/images/vtrack.png', 0, 0);
            this._thumb = new UIImage('http://static.openheatmap.com/images/vthumb.png', 0, 0);        
        }
        else
        {
            this._trackStart = new UIImage('http://static.openheatmap.com/images/track.png', 0, 0);
            this._trackMid = new UIImage('http://static.openheatmap.com/images/track.png', 0, 0);
            this._trackEnd = new UIImage('http://static.openheatmap.com/images/track.png', 0, 0);        
            this._thumb = new UIImage('http://static.openheatmap.com/images/thumb.png', 0, 0);        
        }

        this._isDragging = false;
        this._changeCallback = changeCallback;
    };
    
    this.click = function(event)
    {
        var result = this.handleMouseEvent(event);

        return result;
    };

    this.mousedown = function(event)
    {
        var result = this.handleMouseEvent(event);
        
        if (!result)
            this._isDragging = true;
        
        return result;
    };

    this.mousemove = function(event)
    {
        if (!this._isDragging)
            return true;

        var mouseX = event.localX;
        var mouseY = event.localY;
            
        this.setSliderFromMousePosition(mouseX, mouseY);
    
        return false;
    };
    
    this.mouseup = function(event)
    {
        if (!this._isDragging)
            return true;

        this._isDragging = false;

        var mouseX = event.localX;
        var mouseY = event.localY;
            
        this.setSliderFromMousePosition(mouseX, mouseY);
    
        return false;
    };
    
    this.handleMouseEvent = function(event)
    {
        if (!this._trackStart._isLoaded ||
            !this._trackMid._isLoaded ||
            !this._trackEnd._isLoaded ||
            !this._thumb._isLoaded ||
            !this._isVisible)
            return true;

        var mouseX = event.localX;
        var mouseY = event.localY;
            
        var trackBox = new Rectangle(this._x, this._y, this._width, this._height);
                
        if (!trackBox.contains(mouseX, mouseY))
            return true;
            
        this.setSliderFromMousePosition(mouseX, mouseY);
        
        return false;    
    };

    this.setSliderFromMousePosition = function(mouseX, mouseY)
    {
        if (this._isVertical)
        {
            var minValue = (this._y+this._height);
            var maxValue = this._y;
            var currentValue = mouseY;
        }
        else
        {
            var minValue = this._x;
            var maxValue = (this._x+this._width);
            var currentValue = mouseX;        
        }
        var normalizedValue = ((currentValue-minValue)/(maxValue-minValue));
        normalizedValue = Math.max(0, normalizedValue);
        normalizedValue = Math.min(1, normalizedValue);        
    
        this.setSliderValue(normalizedValue);
        
        if (typeof this._changeCallback !== 'undefined')
            this._changeCallback(this._isDragging);
    };
    
    this.setSliderValue = function(value)
    {
        var normalizedValue = Math.max(0, value);
        normalizedValue = Math.min(1, normalizedValue);        

        this._value = normalizedValue;
                
    };
    
    this.getSliderValue = function()
    {
        return this._value;
    };
    
    this.draw = function(context)
    {
        if (!this._trackStart._isLoaded ||
            !this._trackMid._isLoaded ||
            !this._trackEnd._isLoaded ||
            !this._thumb._isLoaded ||
            !this._isVisible)
            return;
            
        var x = this._x;
        var y = this._y;

        var width;
        var height;
        if (this._isVertical)
        {
            width = this._trackBreadth;
            height = this._capLength;
        }
        else
        {
            width = this._capLength;        
            height = this._trackBreadth;
        }
    
        context.drawImage(this._trackStart._image, x, y, width, height);    

        if (this._isVertical)
        {
            y += height;
            height = (this._height-(this._capLength*2));
        }
        else
        {
            x += width;
            width = (this._width-(this._capLength*2));
        }

        context.drawImage(this._trackMid._image, x, y, width, height);    

        if (this._isVertical)
        {
            y += height;
            height = this._capLength;
        }
        else
        {
            x += width;
            width = this._capLength;
        }

        context.drawImage(this._trackEnd._image, x, y, width, height);    

        if (this._isVertical)
        {
            var minValue = (this._y+this._height);
            var maxValue = this._y;
        }
        else
        {
            var minValue = this._x;
            var maxValue = (this._x+this._width);
        }
    
        var pixelValue = (minValue+(this._value*(maxValue-minValue)));
        
        if (this._isVertical)
        {
            x = (this._x-2);
            y = (pixelValue-3);
        }
        else
        {
            x = (pixelValue-3);
            y = (this._y-2);
        }

        context.drawImage(this._thumb._image, x, y);    
    };
    
    this.__constructor(x, y, width, height, changeCallback);
    
    return this;
}

function UIText(text, font, x, y, clickCallback, alignment)
{
    this.__constructor = function(text, font, x, y, clickCallback, alignment)
    {
        this._text = text;
        this._font = font;
        this._x = x;
        this._y = y;
        this._clickCallback = clickCallback;
        
        if (typeof alignment === 'undefined')
            alignment = 'left';
        this._alignment = alignment;
        
        this._backgroundWidth = 0;
        this._backgroundHeight = 0;
        this._backgroundColor = '';        
    };
    
    this.draw = function(context)
    {
        context.font = this._font;
        
        var textLines = this._text.split('&lt;br/&gt;');
        
        var lineHeight = 22;
        
        var linesCount = textLines.length;
        
        var maxTextWidth = 0;
        for (var lineIndex in textLines)
        {
            var line = textLines[lineIndex];
            var metrics = context.measureText(line);
            var textWidth = (metrics.width+10);
            maxTextWidth = Math.max(textWidth, maxTextWidth);
        }
                
        this._width = maxTextWidth;
        this._height = (linesCount*lineHeight);

        if (this._backgroundWidth>0)
        {
            var backgroundWidth = Math.max(this._backgroundWidth, this._width);
            var backgroundHeight = Math.max(this._backgroundHeight, this._height); 
            var x = (this._x-((backgroundWidth-this._backgroundWidth)/2));
        
            context.fillStyle = this._backgroundColor;
            context.fillRect(x, this._y, backgroundWidth, backgroundHeight);
            context.fillStyle = '#000000';
            context.strokeRect(x, this._y, backgroundWidth, backgroundHeight);
        }
                    
        var x;
        if ((this._backgroundWidth<1)||(this._alignment==='left'))
        {
            x = this._x;
        }
        else if (this._alignment==='center')
        {
            x = this._x+((this._backgroundWidth-this._width)/2);
        }
        else
        {
            x = this._x+(this._backgroundWidth-this._width);        
        }
        
        x += 5;
        
        for (var lineIndex in textLines)
        {
            var line = textLines[lineIndex];
            var currentY = (this._y+(lineHeight*((Number)(lineIndex)+1)));
            currentY -= 5;
            context.fillText(line, x, currentY);
        }
    };
    
    this.setText = function(text)
    {
        this._text = text;
    };
    
    this.setBackground = function(w, h, color)
    {
        this._backgroundWidth = w;
        this._backgroundHeight = h;
        this._backgroundColor = color;
    };
    
    this.click = function(event)
    {
        var mouseX = event.localX;
        var mouseY = event.localY;
            
        var trackBox = new Rectangle(this._x, this._y, this._width, this._height);
                
        if (!trackBox.contains(mouseX, mouseY))
            return true;

        if (typeof this._clickCallback !== 'undefined')
            this._clickCallback();

        return false;
    
    };
    
    this.__constructor(text, font, x, y, clickCallback, alignment);
    
    return this;
}

function UIButton(x, y, width, height, onImage, offImage, changeCallback)
{
    this.__constructor = function(x, y, width, height, onImage, offImage, changeCallback)
    {
        this._x = x;
        this._y = y;
        this._width = width;
        this._height = height;
        this._onImage = new UIImage(onImage, 0, 0);
        this._offImage = new UIImage(offImage, 0, 0);        
        this._changeCallback = changeCallback;

        this._isOn = false;
    };
    
    this.getIsOn = function()
    {
        return this._isOn;
    };
    
    this.setIsOn = function(isOn)
    {
        this._isOn = isOn;
    };
    
    this.draw = function(context)
    {
        if (!this._onImage._isLoaded ||
            !this._offImage._isLoaded)
            return;

        if (this._isOn)
            context.drawImage(this._onImage._image, this._x, this._y);
        else
            context.drawImage(this._offImage._image, this._x, this._y);
    }

    this.click = function(event)
    {
        if (!this._onImage._isLoaded ||
            !this._offImage._isLoaded)
            return true;

        var mouseX = event.localX;
        var mouseY = event.localY;
            
        var trackBox = new Rectangle(this._x, this._y, this._width, this._height);
                
        if (!trackBox.contains(mouseX, mouseY))
            return true;

        this._isOn = !this._isOn;

        if (typeof this._changeCallback !== 'undefined')
            this._changeCallback(this);

        return false;
    };

    this.__constructor(x, y, width, height, onImage, offImage, changeCallback);
    
    return this;
}