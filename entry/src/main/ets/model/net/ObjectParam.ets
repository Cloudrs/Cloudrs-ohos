
export class ObjectSrc {
  items: string[] = []
  dirs: string[] = []

  constructor(items?: string[], dirs?: string[]) {
    if (items) {
      this.items = items
    }
    if (dirs) {
      this.dirs = dirs
    }
  }
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

export class ObjectUpload {
  path: string = ''
  size: number = 0
  name: string = ''
  policy_id: string = ''
  last_modified: number = 0
  mime_type: string = ''

  constructor(path: string, size: number, name: string, policy_id: string, last_modified: number) {
    this.path = path
    this.size = size
    this.name = name
    this.policy_id = policy_id
    this.last_modified = last_modified
  }
}