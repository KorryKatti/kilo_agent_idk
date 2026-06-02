# Kilo Agent / Kilo-Zig

A personal fork of [Kilo](https://github.com/antirez/kilo) focused on rewriting the editor in Zig and exploring Gleam-based agents.

### Components

1.  **Zig Rewrite:** Porting the core editor logic to **Zig 0.14.0**. This implementation follows the ["Build Your Own Text Editor"](https://viewsourcecode.org/snaptoken/kilo/) guide. The original `kilo.c` and `Makefile` have been removed to favor a clean-slate Zig implementation. I am using 0.14.0 because i have only read its documentation and newer version have some different io methods and i dont wanna read.

2.  **Gleam AI Agents:** A concurrent agent framework built in **Gleam**, inspired by [tau](https://github.com/infatoshi/tau) (originally in Rust). The goal is to integrate these agents with the Zig editor for features like code generation and refactoring.

<!--lightweight cursor lmao-->

idk how long will this take but the zig rewrite will definetly be done

### Project Structure
- `kilo-zig/`: The Zig implementation.
- `agent/`: The Gleam agent framework.
- `kilo_to_zig_editor.md` & `gleam_agent_plan.md`: Documentation and roadmaps.
