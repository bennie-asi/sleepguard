import Darwin

@main enum SleepGuardMonitor {
    static func main() {
        exit(MonitorHelper.run(arguments: Array(CommandLine.arguments.dropFirst())))
    }
}
