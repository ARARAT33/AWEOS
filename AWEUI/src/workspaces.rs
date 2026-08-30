#[derive(Debug, Clone)]
pub struct Workspace {
    pub id: usize,
    pub name: String,
    pub active: bool,
}

pub struct WorkspaceManager {
    pub workspaces: Vec<Workspace>,
    pub active_index: usize,
}

impl WorkspaceManager {
    pub fn new(count: usize) -> Self {
        let count = count.max(1);
        let mut workspaces = Vec::new();
        for i in 0..count {
            workspaces.push(Workspace {
                id: i,
                name: format!("Workspace {}", i + 1),
                active: i == 0,
            });
        }
        Self {
            workspaces,
            active_index: 0,
        }
    }

    pub fn switch_to(&mut self, index: usize) {
        if index < self.workspaces.len() {
            for (i, ws) in self.workspaces.iter_mut().enumerate() {
                ws.active = i == index;
            }
            self.active_index = index;
        }
    }

    pub fn current(&self) -> &Workspace {
        &self.workspaces[self.active_index]
    }

    pub fn add_workspace(&mut self, name: Option<String>) -> usize {
        let id = self.workspaces.len();
        let ws_name = name.unwrap_or_else(|| format!("Workspace {}", id + 1));
        self.workspaces.push(Workspace {
            id,
            name: ws_name,
            active: false,
        });
        id
    }
}
