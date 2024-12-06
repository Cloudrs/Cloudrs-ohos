
export class ObjectSrc {
  items: string[] = []
  dirs: string[] = []
}

export class ObjectRename {
  action: string = 'rename'
  src: ObjectSrc = new ObjectSrc()
  new_name: string = ''

  constructor(src: ObjectSrc, new_name: string) {
    this.src = src
    this.new_name = new_name
  }
}

export class ObjectMove {
  action: string = 'move'
  src_dir: string = ''
  src: ObjectSrc = new ObjectSrc()
  dst: string = ''

  constructor(src_dir: string, src: ObjectSrc, dst: string) {
    this.src_dir = src_dir
    this.src = src
    this.dst = dst
  }
}

export class ObjectCopy {
  src_dir: string = ''
  src: ObjectSrc = new ObjectSrc()
  dst: string = ''

  constructor(src_dir: string, src: ObjectSrc, dst: string) {
    this.src_dir = src_dir
    this.src = src
    this.dst = dst
  }
}

export class ObjectNew {
  path: string = ''

  constructor(path: string) {
    this.path = path
  }
}