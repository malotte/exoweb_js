'use strict';

/* Services */

var exowebServices = angular.module('exowebServices', []);

exowebServices.factory('Redirect', [
    function() {

	// Remove when made ngCookies work
	var getCookie = function(cname) {
	    var name = cname + "=";
	    var ca = document.cookie.split(';');
	    window.console.debug("getCookie => " +ca);
	    for(var i=0; i<ca.length; i++) {
		var c = ca[i];
		while (c.charAt(0)==' ') c = c.substring(1);
		if (c.indexOf(name) != -1) 
		    return c.substring(name.length, c.length);
	    }
	    return "";
	};

	var parseUserReply = function(user, reply) {
	    if (reply.value[0] == "ok") {		       
		if (reply.value[0] == "ok") {
		    // Call performed
		    var result = reply.value[1];
		    window.console.debug("Result = " +result.value[1]);
		    if (result.value[0] == "ok") {
			// call successful => {ok,{ok,User}}
			user = result.value[1];
		    }
		    else if (result.value[0] == "error") {
			// Call failed => {ok,{error,Reason}}
			window.alert("Error: " +result.value[1]);
		    }
		}
		else if (reply.value[0] == "error") {
		    // Call not performed => {error, Reason}
		    window.alert("Error: " +reply.value[1]);
		}
	    }
	};
	
	return function(user) {
	    var cookie = getCookie("id");
	    window.console.debug("Cookie = " +cookie);
	    if (cookie == "") {
		window.console.debug("Empty cookie, redirecting!");
		window.location.href = "#/login";
	    }
	    else {
		Wse.call('exoweb_js', 'wrapper', 
			 [Ei.atom('exoweb_login'),  // Module
			  Ei.atom('event'),          // Function
			  Ei.tuple(Ei.atom('user'),[])], // Args
			 // reply callback
			 function(obj,ref,reply) {  
			     window.console.debug("Reply = " +reply);
			     parseUserReply(user, reply);
			 })
	    }
	};
    }]);

exowebServices.factory('DeviceDummy', ['ExowebError',
    function(ExowebError) {
	return function() {
	    window.alert("Dummy called.");
	}}]);
 
exowebServices.factory('DeviceList', ['ExowebError',
    function(ExowebError) {

	var devices = [];

	function fillTable(dataArray, callback) {
	    var i;
	    // Loop over devices
	    for (i=0; i < dataArray.length; i++){
		var j, attArray;
		var device = new Object;
		dataArray[i] = Wse.decode_js(dataArray[i]);
		attArray =  dataArray[i].attributes;
		device["id"] = (dataArray[i])["device-id"];
		// Loop over atttributes
		for (j=0; j < attArray.length; j++)
		    device[attArray[j].name] = attArray[j].val;
		// Make status attribute understandable
		// Can't use field with "-" in name in ng-grid
		if (device["is-connected"] == "true") 
		     device["status"] = "Connected";
		 else
		      device["status"] = "Not connected";
		devices[i] = device;
		window.console.debug("Device " + i + " = " + devices[i]);
	    }
	    callback();
	};


	function parseListReply(reply, callback) {
	    if (reply.value[0] == "ok") {		       
	      if (reply.value[0] == "ok") {
		  // Call performed
		  var result;
		  result = reply.value[1];
		  window.console.debug("Result = " +result.value[1]);
		  if (result.value[0] == "ok") {
		      // call successful => {ok,{ok, Data}}
		      fillTable(result.value[1], callback);
		  }
		  else if (result.value[0] == "error") {
		      // Call failed => {ok,{error,Reason}}
		      ExowebError(result.value[1]);
		  }
	      }
	      else if (reply.value[0] == "error") {
		  // Call not performed => {error, Reason}
		  window.alert("Error: " +reply.value[1]);
	      }
	  }
	};

	var getData = 
	    function(pagingOptions, selectOptions, filterOptions, callback) {
	    setTimeout(function () {
		Wse.call('exoweb_js', 'wrapper', 
			 [Ei.atom('exoweb_device'),  // Module
			  Ei.atom('event'),          // Function
			  Ei.tuple(Ei.atom('load'),  // Args
				   [Ei.tuple(Ei.atom('rows'), 
					     pagingOptions.pageSize),
				    Ei.tuple(Ei.atom('page'), 
					     pagingOptions.currentPage),
				    Ei.tuple(Ei.atom('lastpage'), 
					     selectOptions.lastPage),
				    Ei.tuple(Ei.atom('lastid'), 
					     selectOptions.lastId),
				    Ei.tuple(Ei.atom('match'), 
					     filterOptions.filterText)])], 
			 // reply callback
			 function(obj,ref,reply) {  
			     window.console.debug("Value = " +reply);
			     parseListReply(reply, callback);
			 });
	    }, 100);
	};
	
	return {
	    devices: devices,
	    getData: getData
	};
	
    }]);

exowebServices.factory('DeviceDetail', ['ExowebError',
    function(ExowebError) {
	var device = new Object;
	
	var displayDevice = function (attArray, callback) {
	    attArray = Wse.decode_js(attArray);
	    var i, attArray;
	    // Loop over atttribute objects and set display fields
	    for (i=0; i < attArray.length; i++){
		window.console.debug("Attribute = " +attArray[i].name);
		window.console.debug("Value = " +attArray[i].val);
		switch(attArray[i].name) {
		case "msisdn": device.msisdn = attArray[i].val; break;
		case "device-key": device.devicekey = attArray[i].val; break;
		case "server-key": device.serverkey = attArray[i].val; break;
		case "is-connected": 
		    if (attArray[i].val == "true")
			device.status = "Connected";
		    else if (attArray[i].val == "false")
			device.status = "Not connected"; 
		    break;
		default: window.console.debug("Unknown attribute = " +attArray[i].name);
		}
	    }
	    callback();
	};

	var parseDeviceReply = function(reply, callback) {
	  if (reply.value[0] == "ok") {		       
	      if (reply.value[0] == "ok") {
		  // Call performed
		  var result = reply.value[1];
		  window.console.debug("Result = " +result.value[1]);
		  if (result.value[0] == "ok") {
		      // call successful => {ok,{ok, Device}}
		      window.console.debug("Device = " +result.value[1]);
		      displayDevice(result.value[1], callback);
		      }
		  else if (result.value[0] == "error") {
		      // Call failed => {ok,{error,Reason}}
		      var error = new ExowebError();
		      error.handle(result.value[1]);
		  }
	      }
	      else if (reply.value[0] == "error") {
		  // Call not performed => {error, Reason}
		  window.alert("Error: " +reply.value[1]);
	      }
	  };
	};

	
	var getData = function(deviceid, callback) {
	    device.deviceid = deviceid;
	    Wse.call('exoweb_js', 'wrapper', 
		     [Ei.atom('exoweb_device'),  // Module
		      Ei.atom('event'),          // Function
		      Ei.tuple(Ei.atom('select'), // Args
			       [Ei.tuple(Ei.atom('device-id'), deviceid)])], 
		     // reply callback
		     function(obj,ref,reply) {  
			 window.console.debug("Value = " +reply);
			 parseDeviceReply(reply, callback);
		     });
	}

	return {
	    device: device,
	    getData: getData
	}
    }]);
		

exowebServices.factory('ExowebError', [
    function() {
	return function(error) {
		if (error == "illegal_cookie") {
		    window.console.debug("Go to login");
		    window.location.href = "#/login";
		}
		else {
		    window.alert("Error: " +result.value[1]);
		}
	    }
	}]);
		
	
/*exowebServices.factory('Device', ['$resource',
  function($resource){
    return $resource('https://localhost:8000/exodm/rpc', {}, {
	query: {method:'POST', 
		data:
		'{"json-rpc": "2.0", "method": "exodm:list-devices", "id": "1","params": {"n": 10,"previous": ""}}', 
		headers:{"Authorization": "Basic " +btoa("m17/admin:111111") },
		isArray:true}
    });
  }]);
*/