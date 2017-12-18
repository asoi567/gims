Shoes.app height: 750, width: 1200 do
  flow do
    stack width: 150 do
      @open_bmp_button = button 'Open BMP'
      @save_bmp_button = button 'Save BMP', state: 'disabled'

      @open_custom_button = button 'Open Custom'
      @save_custom_button = button 'Save Custom', state: 'disabled'
    end

    stack width: -150 do
      @meta = para
      @canvas = flow
    end
  end

  @open_bmp_button.click do
    filename = ask_open_file
    if filename
      @file = ProcessedFile.bmp(filename)
      @save_bmp_button.state = nil
      @save_custom_button.state = nil
      @meta.text = @file.meta.inspect
      @canvas.height = @file.height * 2
      @canvas.width = @file.width * 2
      @canvas.clear do
        image do
          @file.pixels.each_with_index do |row, x|
            row.each_with_index do |cell, y|
              stroke rgb(*cell)
              rect x * 2 + 1, y * 2 + 1, 1, 1
            end
          end
        end
      end
    end
  end

  @save_bmp_button.click do
    filename = ask_save_file
    if filename
      @file.to_bmp("#{filename}.bmp")
    end
  end
end

class ProcessedFile
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
          pixels[x] << [f.read(1).unpack("C").first, f.read(1).unpack("C").first, f.read(1).unpack("C").first].reverse
        end
        f.pos += meta[:width] % 4
      end
    end

    new pixels.reverse.transpose, meta
  end

  def self.custom(filename)
  end

  attr_reader :pixels, :meta

  def initialize(pixels, meta = {})
    @pixels = pixels
    @meta = meta
  end

  def to_bmp(filename)
    File.open filename, 'wb' do |f|
      f << ["BM", 54 + pixel_array_size, 0, 0, 54].pack("A2Vv2V")
      f << [40, width, height, 1, 24, 0, pixel_array_size, 2835, 2835, 0, 0].pack("Vl<2v2V2l<2V2")
      pixels.transpose.reverse.map do |row|
        row.map do |pixel|
          f << pixel.reverse.map(&:chr).join
        end
        f << "\x0" * (width % 4)
      end
    end
  end

  def pixel_array_size
    ((24 * width) / 32.0).ceil * 4 * height
  end

  def to_custom
  end

  def height
    pixels.first.length
  end

  def width
    pixels.length
  end
end
