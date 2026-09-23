#[derive(Debug, Clone)]
pub struct Output { pub name:String, pub width:i32, pub height:i32, pub refresh_mhz:i32, pub scale:i32, pub x:i32, pub y:i32 }

pub struct OutputManager { pub outputs:Vec<Output> }
impl OutputManager {
    pub fn new()->Self{Self{outputs:Vec::new()}}
    pub fn create_output(&mut self,name:&str,width:i32,height:i32,refresh_mhz:i32,scale:i32)->Output{
        let x=self.outputs.iter().map(|o|o.width).sum();
        let o=Output{name:name.into(),width,height,refresh_mhz,scale,x,y:0}; self.outputs.push(o.clone()); o
    }
    pub fn primary(&self)->Option<&Output>{self.outputs.first()}
    pub fn total_geometry(&self)->(i32,i32){(self.outputs.iter().map(|o|o.width).sum(),self.outputs.iter().map(|o|o.height).max().unwrap_or(0))}
}
