import Foundation

final class XMLTree {
    let name: String
    var attrs: [String: String] = [:]
    var text = ""
    var children: [XMLTree] = []

    init(name: String) { self.name = name }

    static func parse(_ data: Data) -> XMLTree? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.parse()
        return builder.root
    }

    func all(_ local: String) -> [XMLTree] {
        children.flatMap { ($0.name == local ? [$0] : []) + $0.all(local) }
    }

    func first(_ local: String) -> XMLTree? { all(local).first }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLTree?
        var stack: [XMLTree] = []

        static func local(_ s: String) -> String { s.split(separator: ":").last.map(String.init) ?? s }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let node = XMLTree(name: Builder.local(elementName))
            for (k, v) in attributeDict { node.attrs[Builder.local(k)] = v }
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if let node = stack.popLast() {
                node.text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}
