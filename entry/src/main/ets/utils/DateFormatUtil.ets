export class DateFormatUtil {
  static format(date: Date, pattern: string = 'yyyy-MM-dd HH:mm:ss'): string {
    if (Number.isNaN(date.getTime())) {
      return '-'
    }

    const values: Record<string, string> = {
      'yyyy': date.getFullYear().toString(),
      'MM': DateFormatUtil.pad(date.getMonth() + 1),
      'dd': DateFormatUtil.pad(date.getDate()),
      'HH': DateFormatUtil.pad(date.getHours()),
      'mm': DateFormatUtil.pad(date.getMinutes()),
      'ss': DateFormatUtil.pad(date.getSeconds())
    }

    let result = pattern
    Object.keys(values).forEach((key: string) => {
      result = result.replace(key, values[key])
    })
    return result
  }

  private static pad(value: number): string {
    return value < 10 ? `0${value}` : value.toString()
  }
}
