Shoes.app height: 750, width: 1200 do
  flow do
    stack width: 150 do
      @open_bmp_button = button 'Open BMP'
      @save_bmp_button = button 'Save BMP', state: 'disabled'

      @open_custom_button = button 'Open Custom'
      @save_custom_button = button 'Save Custom', state: 'disabled'

      @noise_probability = edit_line
      @noise_probability.text = '0.001'
      @add_noise_button = button 'Add Noise', state: 'disabled'

      @remove_noise_threshold = edit_line
      @remove_noise_threshold.text = '0.1'
      @remove_noise_button = button 'Remove Noise', state: 'disabled'

      @find_paths_threshold = edit_line
      @find_paths_threshold.text = '0.2'
      @find_paths_button = button 'Find Paths', state: 'disabled'
    end

    stack width: -150 do
      @meta = para
      @canvas = flow
    end
  end

  @open_bmp_button.click do
    filename = ask_open_file
    if filename
      @image = Image.bmp(filename)
      draw_image
    end
  end

  @save_bmp_button.click do
    filename = ask_save_file
    if filename
      @image.to_bmp("#{filename}.bmp")
    end
  end

  @open_custom_button.click do
    filename = ask_open_file
    if filename
      @image = Image.custom(filename)
      draw_image
    end
  end

  @save_custom_button.click do
    filename = ask_save_file
    if filename
      @image.to_custom("#{filename}.bc")
    end
  end

  @add_noise_button.click do
    @image.add_noise(@noise_probability.text.to_f)
    draw_image
  end

  @remove_noise_button.click do
    @image.remove_noise(@remove_noise_threshold.text.to_f)
    draw_image
  end

  @find_paths_button.click do
    @image.find_paths(@find_paths_threshold.text.to_f)
    draw_image
  end

  def draw_image
    @save_bmp_button.state = nil
    @save_custom_button.state = nil
    @add_noise_button.state = nil
    @remove_noise_button.state = nil
    @find_paths_button.state = nil
    @meta.text = @image.meta.inspect
    @canvas.height = @image.height * 2
    @canvas.width = @image.width * 2
    @canvas.clear do
      image do
        @image.pixels.each_with_index do |row, x|
          row.each_with_index do |cell, y|
            stroke rgb(*cell)
            rect x * 2 + 1, y * 2 + 1, 1, 1
          end
        end
      end
    end
  end
end

class Image
  # https://practicingruby.com/articles/binary-file-formats
  def self.bmp(filename)
    meta = {}
    pixels = []
    File.open filename, 'rb' do |f|
      header = f.read(14)
      meta[:type], meta[:file_size], _, _, meta[:off_bits] = header.unpack("A2Vv2V")

      header = f.read(40)
      meta[:size], meta[:width], meta[:height], meta[:planes], meta[:bits_per_pixel],
      meta[:compression_method], meta[:image_size], meta[:hres], meta[:vres],
      meta[:n_colors], meta[:i_colors] = header.unpack("Vl<2v2V2l<2V2")

      meta[:height].times do |x|
        pixels[x] = []
        meta[:width].times do
          pixels[x] << f.read(3).unpack("C3").reverse
        end
        f.pos += meta[:width] % 4
      end
    end

    new pixels.reverse.transpose, meta
  end

  def self.custom(filename)
    meta = {}
    pixels = []
    File.open filename, 'rb' do |f|
      header = f.read(12)
      meta[:type], meta[:file_size], meta[:pixels_size], meta[:off_bits] = header.unpack("A2V2v")

      header = f.read(25)
      meta[:bits_per_pixel], meta[:width], meta[:author] = header.unpack("cVA20")

      height = (meta[:pixels_size] * 3.0 / meta[:width]).floor

      meta[:width].times do |x|
        pixels[x] = []
        height.times do
          pixels[x] << f.read(3).unpack("C3")
        end
      end
    end

    new pixels, meta
  end

  attr_reader :pixels, :meta

  def initialize(pixels, meta = {})
    @pixels = pixels
    @meta = meta
  end

  def to_bmp(filename)
    File.open filename, 'wb' do |f|
      f << ["BM", 54 + bmp_pixel_array_size, 0, 0, 54].pack("A2Vv2V")
      f << [40, width, height, 1, 24, 0, bmp_pixel_array_size, 2835, 2835, 0, 0].pack("Vl<2v2V2l<2V2")
      pixels.transpose.reverse.map do |row|
        row.map do |pixel|
          f << pixel.reverse.pack('c3')
        end
        f << "\x0" * (width % 4)
      end
    end
  end

  def bmp_pixel_array_size
    ((24 * width) / 32.0).ceil * 4 * height
  end

  # 1. идентификатор типа файла (2 байта)
  # 2. размер файла в байтах (4 байта)
  # 4. размер растра в байтах (4 байта)
  # 3. размер заголовка в байтах (2 байта)
  # 9. глубина цвета (количество бит на один пиксель) (1 байт)
  # 6. ширина изображения в пикселях (4 байта)
  # 14. автор формата (20 байт)
  def to_custom(filename)
    File.open filename, 'wb' do |f|
      f << ["BC", 37 + custom_pixel_array_size, custom_pixel_array_size, 37].pack("A2V2v")
      f << [24, width, 'Mikhail Dieterle'].pack("cVA20")
      pixels.map do |row|
        row.map do |pixel|
          f << pixel.pack('c3')
        end
      end
    end
  end

  def custom_pixel_array_size
    (width * height * 8 / 24.0).ceil
  end

  def height
    @height ||= pixels.first.length
  end

  def width
    @width ||= pixels.length
  end

  def add_noise(probability)
    (height * width * probability).round.times do
      pixels[rand(width)][rand(height)] = [rand(256), rand(256), rand(256)]
    end
  end

  # Пороговый фильтр с квадратным окном 3х3
  def remove_noise(threshold)
    iterate do |x ,y|
      if (lum(x, y) - avg_lum(x, y)).abs > threshold * 255
        (0..2).map { |n| avg_color(x, y, n).to_i }
      else
        pixels[x][y]
      end
    end
  end

  def avg_color(x, y, n)
    avg(x, y) do |xi, yi|
      pixels[xi][yi][n]
    end
  end

  def avg_lum(x, y)
    avg(x, y) do |xi, yi|
      lum(xi, yi)
    end
  end

  def avg(x, y)
    [x - 1, x, x + 1]
      .product([y - 1, y, y + 1])
      .reject { |xi, yi| xi == x && yi == y }
      .map { |xi, yi| yield(mirrored(xi, yi)) }
      .reduce(:+) / 8
  end

  def mirrored(x, y)
    x = -x if x < 0
    y = -y if y < 0
    x = x - (width - x + 1) * 2 if x >= width
    y = y - (height - y + 1) * 2 if y >= height
    [x, y]
  end

  def lum(x, y)
    pixels[x][y].reduce(:+) / 3.0
  end

  # Метод разностей по столбцам
  def find_paths(threshold)
    iterate do |x, y|
      case
      when x <= 1 || x >= width - 1 || y <= 0 || y >= height - 1
        [0, 0, 0]
      when (lum(x, y) - lum(x - 1,y)).abs > threshold * 255
        [255, 255, 255]
      else
        [0, 0, 0]
      end
    end
  end

  def iterate
    new_pixels = []
    width.times do |x|
      new_pixels[x] = []

      height.times do |y|
        new_pixels[x][y] = yield(x, y)
      end
    end
    @pixels = new_pixels
  end
end
