@import <AppKit/CPPanel.j>

/*

DCFileUploadDelegate protocol
- (void)fileUploadDidBegin:(DCFileUpload)theController;
- (void)fileUploadProgressDidChange:(DCFileUpload)theController;
- (void)fileUploadDidEnd:(DCFileUpload)theController;

*/

@implementation DCFileUpload : CPObject {
	CPString name @accessors;
	float progress @accessors;
	id delegate @accessors;
	CPURL uploadURL @accessors;
	CPDictionary userInfo @accessors;
	CPString responseText @accessors;
	BOOL indeterminate @accessors;

	id file;
	id xhr;
	BOOL isUploading;

	// legacy support
	id legacyForm;
	id legacyFileElement;
	DOMElement _DOMIFrameElement;
}

- (id)initWithFile:(id)theFile {
	self = [super init];
	file = theFile;
	progress = 0.0;
	isUploading = NO;
	return self;
}

- (id)initWithForm:(id)theForm fileElement:(id)theFileElement {
	self = [super init];
	legacyForm = theForm;
	legacyFileElement = theFileElement;
	progress = 0.0;
	isUploading = NO;
	return self;
}

- (void)begin {
	if (file) {
		// upload asynchronously with progress in newer browsers
		indeterminate = NO;
		[self processXHR];
	} else if (legacyForm && legacyFileElement) {
		// fall back to legacy iframe upload method
		indeterminate = YES;
		[self uploadInIframe];
	}
}

- (void)processXHR {
	xhr = new XMLHttpRequest();

	var fileUpload = xhr.upload;

/*
	xhr.onprogress = function () {
		console.log("onprogress");
	};
*/
	
	fileUpload.addEventListener("progress", function(event) {
		if (event.lengthComputable) {
			[self setProgress:event.loaded / event.total];
			[self fileUploadProgressDidChange];
		}
	}, false);
	
	fileUpload.addEventListener("load", function(event) {
		CPLog("upload done... now need to download response...");
	}, false);
	
	fileUpload.addEventListener("error", function(evt) {
		CPLog("error: " + evt.code);
	}, false);

	if (!uploadURL) {
		return;
	}

	if ([DCFlllowAPI useTokenAuthenticationMethod]) {
		uploadURL = [CPURL URLWithString:[[DCFlllowAPI sharedAPI] tokenizedURL:[uploadURL absoluteString]]];
	}

	if (!FormData) {
		CPLog("Cancelling Upload: FormData object not found.");
		return;
	}

    xhr.addEventListener("load", function(evt) {
        if (xhr.responseText)
            [self fileUploadDidReceiveResponse:xhr.responseText];
    }, NO);

	xhr.open("POST", [uploadURL absoluteURL]);

	var formdata = new FormData();
	formdata.append("document[name]", file.name);
	//formdata.append("document[document_type]", "image");
	formdata.append("document[revisions_attributes][0][description]", "");
	formdata.append("document[revisions_attributes][0][file]", file);
	xhr.setRequestHeader("If-Modified-Since", "Mon, 26 Jul 1997 05:00:00 GMT");
	xhr.setRequestHeader("Cache-Control", "no-cache");
	xhr.setRequestHeader("X-Requested-With", "XMLHttpRequest");
	xhr.send(formdata);

	[self fileUploadDidBegin];
};

- (void)fileUploadDidDrop {
	if ([delegate respondsToSelector:@selector(fileUploadDidDrop:)]) {
		[delegate fileUploadDidDrop:self];
	}
}

- (void)fileUploadDidBegin {
	isUploading = YES;
	if ([delegate respondsToSelector:@selector(fileUploadDidBegin:)]) {
		[delegate fileUploadDidBegin:self];
	}
}

- (void)fileUploadProgressDidChange {
	isUploading = YES;
	if ([delegate respondsToSelector:@selector(fileUploadProgressDidChange:)]) {
		[delegate fileUploadProgressDidChange:self];
	}
}

- (void)fileUploadDidEnd{
	isUploading = NO;
	if ([delegate respondsToSelector:@selector(fileUploadDidEnd:)])
		[delegate fileUploadDidEnd:self];
}

- (void)fileUploadDidReceiveResponse:(CPString)aResponse
{
    if ([delegate respondsToSelector:@selector(fileUpload:didReceiveResponse:)])
		[delegate fileUpload:self didReceiveResponse:aResponse];
}

- (BOOL)isUploading {
	return isUploading;
}

- (void)cancel {
	isUploading = NO;
	xhr.abort();
}


// ************************* Legacy Browser Support *************************

- (void)uploadInIframe {
	legacyForm.target = "FRAME_"+(new Date());
	legacyForm.action = uploadURL;

	//remove existing parameters
	[self _removeUploadFormElements];

	var _parameters = [CPDictionary dictionaryWithObjectsAndKeys:
		legacyFileElement.value, "document[name]",
		//"image", "document[document_type]",
		"", "document[revisions_attributes][0][description]"
	];

	//append the parameters to the form
	var keys = [_parameters allKeys];
	for (var i = 0, count = keys.length; i<count; i++) {
		var theElement = document.createElement("input");

		theElement.type = "hidden";
		theElement.name = keys[i];
		theElement.value = [_parameters objectForKey:keys[i]];

		legacyForm.appendChild(theElement);
	}

	legacyFileElement.name = "document[revisions_attributes][0][file]";
	legacyForm.appendChild(legacyFileElement);

	if (_DOMIFrameElement) {
		document.body.removeChild(_DOMIFrameElement);
		_DOMIFrameElement.onload = nil;
		_DOMIFrameElement = nil;   
	}

	if (window.attachEvent) {
		_DOMIFrameElement = document.createElement("<iframe id=\"" + legacyForm.target + "\" name=\"" + legacyForm.target + "\" />");	   

		if(window.location.href.toLowerCase().indexOf("https") === 0)
			_DOMIFrameElement.src = "javascript:false";
	} else {
		_DOMIFrameElement = document.createElement("iframe");
		_DOMIFrameElement.name = legacyForm.target;	
	}

	_DOMIFrameElement.style.width = "1px";
	_DOMIFrameElement.style.height = "1px";
	_DOMIFrameElement.style.zIndex = -1000;
	_DOMIFrameElement.style.opacity = "0";
	_DOMIFrameElement.style.filter = "alpha(opacity=0)";

	document.body.appendChild(_DOMIFrameElement);

	_onloadHandler = function() {
		try {
			CATCH_EXCEPTIONS = NO;
			responseText = _DOMIFrameElement.contentWindow.document.body ? _DOMIFrameElement.contentWindow.document.body.innerHTML : 
																			   _DOMIFrameElement.contentWindow.document.documentElement.textContent;

			[self fileUploadDidEnd];

			window.setTimeout(function(){
				document.body.removeChild(_DOMIFrameElement);
				_DOMIFrameElement.onload = nil;
				_DOMIFrameElement = nil;
			}, 100);
			CATCH_EXCEPTIONS = YES;
		} catch (e) {
			[self uploadDidFailWithError:e];
		}
	}	 

	if (window.attachEvent) {
		_DOMIFrameElement.onreadystatechange = function() {
			if (this.readyState == "loaded" || this.readyState == "complete")
				_onloadHandler();
		}
	}

	_DOMIFrameElement.onload = _onloadHandler;

	legacyForm.submit();

	[self fileUploadDidBegin];
}

- (void)_removeUploadFormElements {
    var index = legacyForm.childNodes.length;
    while(index--)
        legacyForm.removeChild(legacyForm.childNodes[index]);    
}

- (void)uploadDidFailWithError:(id)error {
	CPLog("uploadDidFailWithError: "+ error);
}

@end
