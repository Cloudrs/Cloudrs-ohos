import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'

const OUTPUT_SIZE: number = 512
const JPEG_QUALITY: number = 90

/**
 * 选一张图，居中裁成正方形，缩到 ≤512 并编码为 JPEG。用户取消返回 undefined。
 * 服务端还会再按自身 MaxWidth 缩放并转 PNG，这里只负责把体积压到合理范围。
 */
export class AvatarPicker {
  static async pickSquareJpeg(): Promise<Uint8Array | undefined> {
    const options = new photoAccessHelper.PhotoSelectOptions()
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
    options.maxSelectNumber = 1
    const result = await new photoAccessHelper.PhotoViewPicker().select(options)
    if (!result.photoUris || result.photoUris.length === 0) {
      return undefined
    }
    const file = fileIo.openSync(result.photoUris[0], fileIo.OpenMode.READ_ONLY)
    let source: image.ImageSource | undefined = undefined
    let pixelMap: image.PixelMap | undefined = undefined
    let packer: image.ImagePacker | undefined = undefined
    try {
      source = image.createImageSource(file.fd)
      const info = await source.getImageInfo()
      const side = Math.min(info.size.width, info.size.height)
      const target = Math.min(side, OUTPUT_SIZE)
      const region: image.Region = {
        x: Math.floor((info.size.width - side) / 2),
        y: Math.floor((info.size.height - side) / 2),
        size: { width: side, height: side }
      }
      pixelMap = await source.createPixelMap({
        desiredRegion: region,
        desiredSize: { width: target, height: target }
      })
      packer = image.createImagePacker()
      const packOptions: image.PackingOption = { format: 'image/jpeg', quality: JPEG_QUALITY }
      const data = await packer.packToData(pixelMap, packOptions)
      return new Uint8Array(data)
    } finally {
      try {
        await packer?.release()
        await pixelMap?.release()
        await source?.release()
      } finally {
        fileIo.closeSync(file)
      }
    }
  }
}
