const fs = require("fs")
const path = require("path")

for (const file of fs.readdirSync(__dirname)){
  let name = file
  if (name.endsWith(".js")){
    name = name.substring(0, name.length - 3) + ".dart"
  }
  let ind = 0
  let outName = ""
  for (const c of name){
    if (ind !== 0 && /[A-Z]/.test(name[ind])) {
      outName += "_" + name[ind].toLowerCase()
    } else {
      outName += name[ind].toLowerCase()
    }
    ind++;
  }
  // console.log(file, name, outName)
  fs.renameSync(path.join(__dirname, file), path.join(__dirname, outName))
}