import Foundation

public enum ClaudeProfileLogin {
    /// Apply the profile after login-shell startup, which may itself set CLAUDE_CONFIG_DIR.
    /// The command contains only a quoted directory and the CLI's explicit login action.
    public static func script(directory: String) -> String {
        let command = "exec /usr/bin/env " + quote("CLAUDE_CONFIG_DIR=" + directory) + " claude auth login"
        return "#!/bin/zsh\n/bin/zsh -l -c " + quote(command) + "\n"
    }
    private static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
