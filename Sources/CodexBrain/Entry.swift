import SwiftUI

@main
enum Main {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if let first = args.first,
           ["ask", "remember", "reindex", "selfcheck", "--selfcheck", "help", "--help"].contains(first) {
            exit(CLI.run(args))
        }
        CodexBrainApp.main()
    }
}
