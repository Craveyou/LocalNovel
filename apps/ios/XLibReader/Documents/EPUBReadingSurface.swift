import AppleShared
import SwiftUI
import WebKit

struct EPUBReadingSurface: UIViewRepresentable {
    let document:ReflowDocument
    let model:DocumentReaderModel
    let settings:ReaderSettings
    let link:(URL)->Void
    var tapped:(()->Void)? = nil
    var interactionEnabled = true
    init(document:ReflowDocument,model:DocumentReaderModel,settings:ReaderSettings,link:@escaping(URL)->Void,tapped:(()->Void)? = nil,interactionEnabled:Bool = true) {
        self.document = document;self.model = model;self.settings = settings;self.link = link;self.tapped = tapped;self.interactionEnabled = interactionEnabled
    }
    init(document:EPUBDocument,model:DocumentReaderModel,settings:ReaderSettings,link:@escaping(URL)->Void) {
        self.init(document:ReflowDocument(document),model:model,settings:settings,link:link)
    }
    func makeCoordinator() -> Coordinator {Coordinator(document:document,model:model,link:link,tapped:tapped)}
    func makeUIView(context:Context) -> UIView {
        let viewport = EPUBViewport()
        viewport.restore = { [weak model] in model?.reflow() }
        return viewport
    }
    func updateUIView(_ container:UIView,context:Context) {
        let coordinator = context.coordinator
        coordinator.interactionEnabled = interactionEnabled
        if model.selection.isEmpty, coordinator.selected {coordinator.web?.evaluateJavaScript("window.getSelection().removeAllRanges()");coordinator.selected = false}
        guard let command = model.command, coordinator.command?.id != command.id, let i = document.chapterIndex(for: command.locator) else {return}
        model.rendererStarted(command.id)
        coordinator.captureTask?.cancel()
        coordinator.command = command;coordinator.restoring = true;coordinator.userMoved = false;coordinator.selected = false
        let style = "\(settings.fontSize)|\(settings.lineSpacing)|\(settings.fontName)|\(settings.theme)"
        coordinator.invalidateStyle(style)
        if let cached = coordinator.pages.first(where:{$0.chapter == i}) {
            coordinator.activate(cached,in:container)
            if let valid = cached.validated {
                if valid { coordinator.position() }
                else { Task { model.rendererCompleted(command.id,success:false) } }
            }
            return
        }
        let page = coordinator.makePage(chapter:i,in:container,background:settings.theme.uiBackground)
        let web = page.web
        let chapter = document.chapters[i]
        let dark = settings.theme == .dark
        let font:String
        switch settings.fontName {
        case "PingFangSC-Regular":font = "'PingFang SC',sans-serif"
        case "Songti SC","serif":font = "'Songti SC',serif"
        case "FangSong":font = "'FangSong',serif"
        case "Menlo","monospace":font = "'Menlo',monospace"
        default:font = "-apple-system,sans-serif"
        }
        // Defer offscreen paragraph layout while preserving the full DOM and text coordinates.
        let longChapterStyle = chapter.text.utf16.count > 262_144 ? "body>p{content-visibility:auto;contain-intrinsic-size:auto 100px}" : ""
        let html = """
        <!doctype html><html data-xlib-generation="\(page.id.uuidString)"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none';img-src xlib-book: data:;style-src 'unsafe-inline' xlib-book:;font-src xlib-book:;script-src 'none';connect-src 'none';form-action 'none';"><style>html{background:\(dark ? "#17201b" : "#f7f8f4")!important;color:\(dark ? "#e5ece7" : "#19271f")!important}body{margin:\(document.isKindle ? "0" : "8px");padding:\(document.isKindle ? "16px 20px" : "16px");text-align:\(document.isKindle ? "justify" : "start");overflow-wrap:anywhere;font-size:\(settings.fontSize)px!important;line-height:\(1+settings.lineSpacing/settings.fontSize)!important;font-family:\(font)!important}html body p,html body div,html body span{font-size:inherit!important;line-height:inherit!important;font-family:inherit!important}body,p,div,span{color:inherit!important;background-color:transparent!important}img{max-width:100%;height:auto}\(longChapterStyle)</style></head>\(chapter.html)</html>
        """
        web.loadHTMLString(html,baseURL:URL(string:"xlib-book://book.xlib.invalid/"+chapter.resource))
    }
    static func dismantleUIView(_ container:UIView,coordinator:Coordinator) {
        (container as? EPUBViewport)?.restore = nil
        coordinator.stop()
    }
    @MainActor final class Coordinator:NSObject,WKNavigationDelegate,WKScriptMessageHandler,UIScrollViewDelegate,UIGestureRecognizerDelegate {
        let document:ReflowDocument
        let model:DocumentReaderModel
        let link:(URL)->Void
        let tapped:(()->Void)?
        var interactionEnabled = true
        weak var web:WKWebView?
        final class Page {
            let id = UUID()
            let chapter:Int
            let web:WKWebView
            var validated:Bool?
            init(chapter:Int,web:WKWebView) {self.chapter = chapter;self.web = web}
        }
        var pages:[Page] = []
        var style:String?
        var command:DocumentReaderModel.Command?
        var restoring = true
        var userMoved = false
        var selected = false
        var captureTask:Task<Void,Never>?
        init(document:ReflowDocument,model:DocumentReaderModel,link:@escaping (URL)->Void,tapped:(()->Void)?) {self.document = document;self.model = model;self.link = link;self.tapped = tapped}
        func invalidateStyle(_ next:String) {
            if style != next { stop();style = next }
        }
        func makePage(chapter:Int,in container:UIView,background:UIColor) -> Page {
            let config = WKWebViewConfiguration();config.websiteDataStore = .nonPersistent()
            config.setURLSchemeHandler(LocalResources(document:document),forURLScheme:"xlib-book")
            config.userContentController.add(self,name:"xlib")
            config.userContentController.addUserScript(WKUserScript(source:EPUBReadingSurface.script,injectionTime:.atDocumentEnd,forMainFrameOnly:true))
            let web = WKWebView(frame:container.bounds,configuration:config)
            web.navigationDelegate = self;web.scrollView.delegate = self
            if document.isKindle {
                let tap = UITapGestureRecognizer(target:self,action:#selector(tapBody(_:)))
                tap.cancelsTouchesInView = false;tap.delegate = self;web.addGestureRecognizer(tap)
            }
            web.accessibilityLabel = document.isKindle ? "Kindle 正文" : "EPUB 正文";web.isOpaque = false;web.backgroundColor = background
            let page = Page(chapter:chapter,web:web)
            pages.append(page);activate(page,in:container)
            // Keep only the current and most recently visited chapter, never an entire book.
            while pages.count > 2 { discard(pages.removeFirst()) }
            return page
        }
        func activate(_ page:Page,in container:UIView) {
            web?.removeFromSuperview();web = page.web
            pages.removeAll {$0 === page};pages.append(page)
            page.web.frame = container.bounds;page.web.autoresizingMask = [.flexibleWidth,.flexibleHeight]
            container.addSubview(page.web)
        }
        private func discard(_ page:Page) {
            page.web.stopLoading();page.web.navigationDelegate = nil;page.web.scrollView.delegate = nil
            page.web.configuration.userContentController.removeScriptMessageHandler(forName:"xlib")
            page.web.configuration.userContentController.removeAllUserScripts();page.web.removeFromSuperview()
        }
        func stop() {
            captureTask?.cancel();captureTask = nil
            for page in pages { discard(page) };pages = [];web = nil
        }
        func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer:UIGestureRecognizer) -> Bool { true }
        @objc private func tapBody(_ recognizer:UITapGestureRecognizer) {
            guard recognizer.state == .ended,let web,recognizer.view === web,model.selection.isEmpty else {return}
            let point = recognizer.location(in:web),ratio = point.x / max(1,web.bounds.width)
            if (web.isLoading || model.rendering), !interactionEnabled || (ratio >= 0.35 && ratio < 0.55) {
                tapped?();return
            }
            // Let native links and text selection keep their own gestures. The
            // menu tap itself is native, not dependent on WebKit click synthesis.
            let script = "(function(){var e=document.elementFromPoint(\(point.x),\(point.y));return window.getSelection().isCollapsed&&!!e&&!e.closest('a');})()"
            web.evaluateJavaScript(script) { [weak self,weak web] value,_ in
                guard let self,let web,self.web === web,value as? Bool == true,self.model.selection.isEmpty else {return}
                if !self.interactionEnabled || (ratio >= 0.35 && ratio < 0.55) { self.tapped?() }
                else { self.turn(ratio < 0.35 ? -1 : 1) }
            }
        }
        func position() {
            guard let command, let offset = document.localOffset(for: command.locator) else {return}
            var script = "window.getSelection().removeAllRanges();window.xlibGo(\(offset))"
            if let range = command.highlight {script += ";window.xlibHighlight(\(range.location),\(range.length))"}
            web?.evaluateJavaScript(script) {[weak self] _,error in
                guard let self,self.command?.id == command.id else {return}
                self.restoring = false;self.model.rendererCompleted(command.id,success:error == nil)
                self.web?.accessibilityIdentifier = error == nil ? "document.content.ready" : "document.content.failed"
                if let chapter = self.document.chapterIndex(for:command.locator) {
                    self.web?.accessibilityValue = "第 \(chapter+1) 章"
                }
            }
        }
        func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  let value = message.body as? [String:Any],let id = value["id"] as? String,
                  let page = pages.first(where:{$0.id.uuidString == id}),message.webView === page.web else {return}
            if page.web === web,let text = value["selected"] as? String {model.selection = document.isKindle ? text.replacingOccurrences(of: "\u{fffc}", with: "") : text;selected = !text.isEmpty}
            guard let text = value["ready"] as? String else {return}
            guard text == document.chapters[page.chapter].text else {
                page.validated = false
                if page.web === web,let command {model.rendererCompleted(command.id,success:false)}
                return
            }
            page.validated = true
            if page.web === web {position()}
        }
        func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction) async -> WKNavigationActionPolicy {
            if action.navigationType == .linkActivated,let url = action.request.url {if webView === web {link(url)};return .cancel}
            let scheme = action.request.url?.scheme
            return scheme == "about" || scheme == "xlib-book" ? .allow : .cancel
        }
        func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) {if webView === web,let command {model.rendererCompleted(command.id,success:false)}}
        func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {
            if webView === web,let command {model.rendererCompleted(command.id,success:false)}
        }
        func webViewWebContentProcessDidTerminate(_ webView:WKWebView) {
            pages.first(where:{$0.web === webView})?.validated = false
            if webView === web,let command {model.rendererCompleted(command.id,success:false)}
        }
        func scrollViewWillBeginDragging(_ scrollView:UIScrollView) {if scrollView === web?.scrollView {userMoved = true}}
        func scrollViewDidScroll(_ scrollView:UIScrollView) {
            guard scrollView === web?.scrollView,userMoved,!restoring else {return}
            captureTask?.cancel()
            captureTask = Task {[weak self] in
                do {try await Task.sleep(for:.milliseconds(300))}catch{return}
                self?.capturePosition()
            }
        }
        func scrollViewDidEndDragging(_ scrollView:UIScrollView,willDecelerate decelerate:Bool) {
            guard scrollView === web?.scrollView else {return}
            captureTask?.cancel();capturePosition()
            if !decelerate {userMoved = false}
        }
        func scrollViewDidEndDecelerating(_ scrollView:UIScrollView) {
            guard scrollView === web?.scrollView else {return}
            captureTask?.cancel();capturePosition();userMoved = false
        }
        private func capturePosition() {
            guard userMoved,!restoring,let command, let i = document.chapterIndex(for: command.locator) else {return}
            web?.evaluateJavaScript("window.getSelection().isCollapsed?window.xlibOffset():-1") {[weak self] value,_ in
                guard let self,self.command?.id == command.id,let offset = value as? Int,offset >= 0 else {return}
                self.model.userScrolled(self.document.locator(chapter:i,offset:offset))
            }
        }
        private func turn(_ delta:Int) {
            guard model.canNavigate,!model.rendering,let command else {return}
            web?.evaluateJavaScript("window.xlibTurn(\(delta))") { [weak self] result,error in
                guard let self,self.command?.id == command.id,error == nil,let result = result as? [String:Any] else {return}
                if result["edge"] as? Bool == true { self.model.moveUnit(delta) }
                else if let offset = result["offset"] as? Int,offset >= 0,let unit = self.document.chapterIndex(for:command.locator) {
                    self.model.userScrolled(self.document.locator(chapter:unit,offset:offset))
                }
            }
        }
    }
    private static let interactionScript = """
    window.xlibTurn=function(delta){var edge=delta<0?window.scrollY<=1:window.scrollY+window.innerHeight>=document.documentElement.scrollHeight-1;if(edge)return {edge:true};window.scrollBy(0,delta*window.innerHeight*0.85);return {edge:false,offset:window.xlibOffset()};};
    """
    static let script = interactionScript + """
    (function(){var id=document.documentElement.getAttribute('data-xlib-generation');if(!id)return;var nodes=[],walk=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,{acceptNode:function(n){return /^(SCRIPT|STYLE)$/.test(n.parentNode.tagName)?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_ACCEPT;}}),n;while(n=walk.nextNode())nodes.push(n);window.xlibNodes=nodes;function at(offset,end){var sum=0;for(var i=0;i<nodes.length;i++){var n=nodes[i];if(sum+n.length>offset||(end&&sum+n.length===offset)||i===nodes.length-1)return [n,Math.max(0,Math.min(n.length,offset-sum))];sum+=n.length;}return null;}window.xlibOffset=function(){var r=document.caretRangeFromPoint(12,20);if(!r)return -1;var sum=0;for(var i=0;i<nodes.length;i++){if(nodes[i]===r.startContainer)return sum+r.startOffset;sum+=nodes[i].length;}return -1;};window.xlibGo=function(offset){var p=at(offset);if(!p)return;p[0].parentElement.scrollIntoView({block:"start"});var r=document.createRange();r.setStart(p[0],p[1]);r.setEnd(p[0],Math.min(p[0].length,p[1]+1));var b=r.getBoundingClientRect();window.scrollTo(0,window.scrollY+b.top-16);};window.xlibHighlight=function(offset,length){var a=at(offset),b=at(offset+length,true);if(!a||!b)return;var r=document.createRange();r.setStart(a[0],a[1]);r.setEnd(b[0],b[1]);var s=window.getSelection();s.removeAllRanges();s.addRange(r);};document.addEventListener('selectionchange',function(){window.webkit.messageHandlers.xlib.postMessage({id:id,selected:String(window.getSelection())});});window.webkit.messageHandlers.xlib.postMessage({id:id,ready:nodes.map(function(n){return n.data;}).join('')});})();
    """
}

private final class EPUBViewport:UIView {
    var restore:(()->Void)?
    private var previousWidth:CGFloat = 0
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        if previousWidth > 0, width > 0, abs(width-previousWidth) > 0.5 {
            // Width changes rewrap text. Selection toolbars only change height and must
            // not clear a new selection or move the reader back to an earlier anchor.
            DispatchQueue.main.async { [weak self] in self?.restore?() }
        }
        previousWidth = width
    }
}

private final class LocalResources:NSObject,WKURLSchemeHandler {
    let document:ReflowDocument
    init(document:ReflowDocument) {self.document = document}
    func webView(_ webView:WKWebView,start task:WKURLSchemeTask) {
        do {
            guard let url = task.request.url,url.scheme == "xlib-book",url.host == "book.xlib.invalid" else {throw DocumentError.unsupported("外部资源被阻止")}
            let path = String(url.path.dropFirst())
            guard DocumentLocator.safeResource(path) else {throw DocumentError.invalidPosition}
            let bytes = try document.read(path)
            let mime:String
            switch url.pathExtension.lowercased() {
            case "css":mime = "text/css"
            case "png":mime = "image/png"
            case "jpg","jpeg":mime = "image/jpeg"
            case "svg":mime = "image/svg+xml"
            case "gif":mime = "image/gif"
            case "woff":mime = "font/woff"
            case "woff2":mime = "font/woff2"
            case "ttf":mime = "font/ttf"
            default:mime = "application/octet-stream"
            }
            task.didReceive(URLResponse(url:url,mimeType:mime,expectedContentLength:bytes.count,textEncodingName:mime == "text/css" ? "utf-8" : nil));task.didReceive(bytes);task.didFinish()
        } catch {task.didFailWithError(error)}
    }
    func webView(_ webView:WKWebView,stop task:WKURLSchemeTask) {}
}
