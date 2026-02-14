use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use clap::{Args, Parser, Subcommand, ValueEnum};
use serde::Serialize;

#[derive(Parser, Debug)]
#[command(name = "x07-mcp")]
#[command(about = "X07 MCP kit tooling (scaffolding, conformance, dev workflows).", long_about = None)]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    cmd: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Scaffolding and template generation.
    Scaffold(ScaffoldArgs),
}

#[derive(Args, Debug)]
struct ScaffoldArgs {
    #[command(subcommand)]
    cmd: ScaffoldCommand,
}

#[derive(Subcommand, Debug)]
enum ScaffoldCommand {
    /// Initialize a new MCP server project from a template.
    Init(ScaffoldInitArgs),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum TemplateName {
    #[value(name = "mcp-server")]
    Server,
    #[value(name = "mcp-server-stdio")]
    ServerStdio,
    #[value(name = "mcp-server-http")]
    ServerHttp,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
#[clap(rename_all = "kebab_case")]
enum MachineMode {
    Json,
}

#[derive(Args, Debug)]
struct ScaffoldInitArgs {
    #[arg(long, value_enum)]
    template: TemplateName,

    #[arg(long, value_name = "PATH")]
    dir: PathBuf,

    #[arg(long, value_name = "SEMVER")]
    toolchain_version: Option<String>,

    #[arg(long, value_enum)]
    machine: Option<MachineMode>,
}

#[derive(Debug, Serialize)]
struct ScaffoldInitError {
    message: String,
}

#[derive(Debug, Serialize)]
struct ScaffoldInitReport {
    ok: bool,
    created: Vec<String>,
    next_steps: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<ScaffoldInitError>,
}

struct TemplateFile {
    rel_path: &'static str,
    contents: &'static [u8],
}

fn template_files(name: TemplateName) -> &'static [TemplateFile] {
    match name {
        TemplateName::Server => &TEMPLATE_MCP_SERVER,
        TemplateName::ServerStdio => &TEMPLATE_MCP_SERVER_STDIO,
        TemplateName::ServerHttp => &TEMPLATE_MCP_SERVER_HTTP,
    }
}

fn write_new_file(abs: &Path, contents: &[u8]) -> std::io::Result<()> {
    if let Some(parent) = abs.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(abs)?;
    use std::io::Write as _;
    f.write_all(contents)?;
    Ok(())
}

fn run_scaffold_init(args: &ScaffoldInitArgs) -> Result<ScaffoldInitReport> {
    let dir = &args.dir;
    std::fs::create_dir_all(dir).with_context(|| format!("create dir: {}", dir.display()))?;

    let files = template_files(args.template);
    let mut created: Vec<String> = Vec::new();
    for f in files {
        let abs = dir.join(f.rel_path);
        write_new_file(&abs, f.contents).with_context(|| format!("write {}", abs.display()))?;
        created.push(f.rel_path.to_string());
    }

    let next_steps: Vec<String> = match args.template {
        TemplateName::ServerStdio => vec![
            format!("cd {}", dir.display()),
            "x07 policy init --template worker --project x07.json".to_string(),
            "x07 pkg add ext-mcp-transport-stdio@0.1.0 --sync".to_string(),
            "x07 pkg add ext-mcp-worker@0.1.0 --sync".to_string(),
            "x07 pkg add ext-mcp-rr@0.1.0 --sync".to_string(),
            "x07 pkg add ext-hex-rs@0.1.4 --sync".to_string(),
            "x07 test --manifest tests/tests.json".to_string(),
            "x07 bundle --profile os --out out/mcp-router".to_string(),
            "x07 bundle --profile sandbox --program src/worker_main.x07.json --out out/mcp-worker"
                .to_string(),
            "./out/mcp-router".to_string(),
        ],
        _ => vec![
            format!("cd {}", dir.display()),
            "x07 run".to_string(),
            "x07 test --manifest tests/tests.json".to_string(),
        ],
    };

    Ok(ScaffoldInitReport {
        ok: true,
        created,
        next_steps,
        error: None,
    })
}

fn main() -> std::process::ExitCode {
    match try_main() {
        Ok(code) => code,
        Err(err) => {
            eprintln!("{err:#}");
            std::process::ExitCode::from(2)
        }
    }
}

fn try_main() -> Result<std::process::ExitCode> {
    let cli = Cli::parse();
    match cli.cmd {
        Command::Scaffold(args) => match args.cmd {
            ScaffoldCommand::Init(args) => {
                let machine_json = args.machine == Some(MachineMode::Json);
                let report = match run_scaffold_init(&args) {
                    Ok(r) => r,
                    Err(err) => ScaffoldInitReport {
                        ok: false,
                        created: Vec::new(),
                        next_steps: Vec::new(),
                        error: Some(ScaffoldInitError {
                            message: format!("{err:#}"),
                        }),
                    },
                };

                if machine_json {
                    println!("{}", serde_json::to_string(&report)?);
                } else if report.ok {
                    println!(
                        "ok: created {} file(s) under {}",
                        report.created.len(),
                        args.dir.display()
                    );
                    for step in &report.next_steps {
                        println!("next: {step}");
                    }
                } else {
                    println!(
                        "error: {}",
                        report
                            .error
                            .as_ref()
                            .map(|e| e.message.as_str())
                            .unwrap_or("failed")
                    );
                }

                Ok(if report.ok {
                    std::process::ExitCode::SUCCESS
                } else {
                    std::process::ExitCode::from(1)
                })
            }
        },
    }
}

const TEMPLATE_MCP_SERVER: [TemplateFile; 8] = [
    TemplateFile {
        rel_path: ".gitignore",
        contents: include_bytes!("../../../templates/mcp-server/.gitignore"),
    },
    TemplateFile {
        rel_path: "README.md",
        contents: include_bytes!("../../../templates/mcp-server/README.md"),
    },
    TemplateFile {
        rel_path: "x07.json",
        contents: include_bytes!("../../../templates/mcp-server/x07.json"),
    },
    TemplateFile {
        rel_path: "x07.lock.json",
        contents: include_bytes!("../../../templates/mcp-server/x07.lock.json"),
    },
    TemplateFile {
        rel_path: "src/app.x07.json",
        contents: include_bytes!("../../../templates/mcp-server/src/app.x07.json"),
    },
    TemplateFile {
        rel_path: "src/main.x07.json",
        contents: include_bytes!("../../../templates/mcp-server/src/main.x07.json"),
    },
    TemplateFile {
        rel_path: "tests/tests.json",
        contents: include_bytes!("../../../templates/mcp-server/tests/tests.json"),
    },
    TemplateFile {
        rel_path: "tests/smoke.x07.json",
        contents: include_bytes!("../../../templates/shared/tests/smoke.x07.json"),
    },
];

const TEMPLATE_MCP_SERVER_STDIO: [TemplateFile; 17] = [
    TemplateFile {
        rel_path: ".gitignore",
        contents: include_bytes!("../../../templates/mcp-server-stdio/.gitignore"),
    },
    TemplateFile {
        rel_path: "README.md",
        contents: include_bytes!("../../../templates/mcp-server-stdio/README.md"),
    },
    TemplateFile {
        rel_path: "x07.json",
        contents: include_bytes!("../../../templates/mcp-server-stdio/x07.json"),
    },
    TemplateFile {
        rel_path: "x07.lock.json",
        contents: include_bytes!("../../../templates/mcp-server-stdio/x07.lock.json"),
    },
    TemplateFile {
        rel_path: "config/mcp.server.json",
        contents: include_bytes!("../../../templates/mcp-server-stdio/config/mcp.server.json"),
    },
    TemplateFile {
        rel_path: "config/mcp.tools.json",
        contents: include_bytes!("../../../templates/mcp-server-stdio/config/mcp.tools.json"),
    },
    TemplateFile {
        rel_path: "src/app.x07.json",
        contents: include_bytes!("../../../templates/mcp-server-stdio/src/app.x07.json"),
    },
    TemplateFile {
        rel_path: "src/main.x07.json",
        contents: include_bytes!("../../../templates/mcp-server-stdio/src/main.x07.json"),
    },
    TemplateFile {
        rel_path: "src/worker_main.x07.json",
        contents: include_bytes!("../../../templates/mcp-server-stdio/src/worker_main.x07.json"),
    },
    TemplateFile {
        rel_path: "src/mcp/user.x07.json",
        contents: include_bytes!("../../../templates/mcp-server-stdio/src/mcp/user.x07.json"),
    },
    TemplateFile {
        rel_path: "tests/tests.json",
        contents: include_bytes!("../../../templates/mcp-server-stdio/tests/tests.json"),
    },
    TemplateFile {
        rel_path: "tests/smoke.x07.json",
        contents: include_bytes!("../../../templates/shared/tests/smoke.x07.json"),
    },
    TemplateFile {
        rel_path: "tests/mcp/tests.x07.json",
        contents: include_bytes!("../../../templates/mcp-server-stdio/tests/mcp/tests.x07.json"),
    },
    TemplateFile {
        rel_path: "tests/fixtures/replay/mcp.server.json",
        contents: include_bytes!(
            "../../../templates/mcp-server-stdio/tests/fixtures/replay/mcp.server.json"
        ),
    },
    TemplateFile {
        rel_path: "tests/fixtures/replay/mcp.tools.json",
        contents: include_bytes!(
            "../../../templates/mcp-server-stdio/tests/fixtures/replay/mcp.tools.json"
        ),
    },
    TemplateFile {
        rel_path: "tests/fixtures/replay/c2s.jsonl",
        contents: include_bytes!("../../../templates/mcp-server-stdio/tests/fixtures/replay/c2s.jsonl"),
    },
    TemplateFile {
        rel_path: "tests/fixtures/replay/s2c.jsonl",
        contents: include_bytes!("../../../templates/mcp-server-stdio/tests/fixtures/replay/s2c.jsonl"),
    },
];

const TEMPLATE_MCP_SERVER_HTTP: [TemplateFile; 8] = [
    TemplateFile {
        rel_path: ".gitignore",
        contents: include_bytes!("../../../templates/mcp-server-http/.gitignore"),
    },
    TemplateFile {
        rel_path: "README.md",
        contents: include_bytes!("../../../templates/mcp-server-http/README.md"),
    },
    TemplateFile {
        rel_path: "x07.json",
        contents: include_bytes!("../../../templates/mcp-server-http/x07.json"),
    },
    TemplateFile {
        rel_path: "x07.lock.json",
        contents: include_bytes!("../../../templates/mcp-server-http/x07.lock.json"),
    },
    TemplateFile {
        rel_path: "src/app.x07.json",
        contents: include_bytes!("../../../templates/mcp-server-http/src/app.x07.json"),
    },
    TemplateFile {
        rel_path: "src/main.x07.json",
        contents: include_bytes!("../../../templates/mcp-server-http/src/main.x07.json"),
    },
    TemplateFile {
        rel_path: "tests/tests.json",
        contents: include_bytes!("../../../templates/mcp-server-http/tests/tests.json"),
    },
    TemplateFile {
        rel_path: "tests/smoke.x07.json",
        contents: include_bytes!("../../../templates/shared/tests/smoke.x07.json"),
    },
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scaffold_init_machine_json_creates_files() {
        let tmp = tempfile::tempdir().expect("tempdir");
        let dir = tmp.path().join("proj");

        let args = ScaffoldInitArgs {
            template: TemplateName::ServerStdio,
            dir: dir.clone(),
            toolchain_version: Some("0.0.0".to_string()),
            machine: Some(MachineMode::Json),
        };
        let report = run_scaffold_init(&args).expect("scaffold init");
        assert!(report.ok);
        assert!(dir.join("x07.json").is_file());
        assert!(dir.join("x07.lock.json").is_file());
        assert!(dir.join("config/mcp.server.json").is_file());
        assert!(dir.join("config/mcp.tools.json").is_file());
        assert!(dir.join("src").is_dir());
        assert!(dir.join("src/worker_main.x07.json").is_file());
        assert!(dir.join("src/mcp/user.x07.json").is_file());
        assert!(dir.join("tests").is_dir());
        assert!(dir.join("tests/mcp/tests.x07.json").is_file());
        assert!(dir.join("tests/fixtures/replay/c2s.jsonl").is_file());
        assert!(dir.join("tests/fixtures/replay/s2c.jsonl").is_file());
        assert!(!report.created.is_empty());
    }
}
