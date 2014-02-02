require 'wavefile'
include WaveFile

$BUFF_CONST = 1024 ** 2 * 5
class State
  HIGH = 1
  LOW = 0
end

def usage
  puts "Usage: ruby cutup.rb wave-file delta sequence out-file";
  exit
end

if ARGV.size < 3 then
  usage
else
  puts "Generate average value"
  Reader.new(ARGV[0]) do |reader|
    $buff_size = $BUFF_CONST
    $wav_eof = false
    $sample_sum = 0
    while (! $wav_eof) do
      if $buff_size > reader.total_sample_frames - reader.current_sample_frame then
        $buff_size = reader.total_sample_frames - reader.current_sample_frame
        $wav_eof = true
      end
      $samples = reader.read($buff_size)
      $sample_sum += ($samples.samples.map { |x| if reader.format.channels == 1 then x.abs else x[0].abs + x[1].abs end}).reduce(:+)
    end
    $avg = $sample_sum.fdiv(reader.total_sample_frames*reader.format.channels)
  end
  puts "Got average amplitude of " + $avg.to_s
  puts "Find split positions"
  Reader.new(ARGV[0]) do |reader|
    $buff_size = $BUFF_CONST
    $wav_eof = false
    $lows = Array.new
    $lows.push 0
    $low_start = 0
    $low_samples = 0
    $state = State::LOW
    $offset = 0
    $min = $avg
    $max = 0
    $longest_low = 0
    $sum_lows = 0
    $count_lows = 0
    while (! $wav_eof) do
#      puts reader.total_sample_frames - reader.current_sample_frame
      if $buff_size > reader.total_sample_frames - reader.current_sample_frame then
        $buff_size = reader.total_sample_frames - reader.current_sample_frame
        $wav_eof = true
      end
      $samples = reader.read($buff_size)
      0.upto $samples.samples.size - 1 do |x|
#        print x.to_s + "\t"
        if reader.format.channels == 1 then
          current = $samples.samples[x].abs
        else
          # to be improved
          current = ($samples.samples[x][0].abs + $samples.samples[x][1].abs) / 2
        end
        if current < $min then
          $min = current
        elsif current > $max then
          $max = current
        end
        if $state == State::LOW && current >= $avg - ARGV[1].to_f then
          $state = State::HIGH
          # puts $low_samples
          if $low_samples > $longest_low then $longest_low = $low_samples end
          $sum_lows += $low_samples
          $count_lows += 1
          if $low_samples > ARGV[2].to_f then
            $lows.push $low_start
          end
        elsif $state == State::HIGH && current < $avg - ARGV[1].to_f then
          $state = State::LOW
          $low_start = x + $offset
          $low_samples = 0
        elsif $state == State::LOW then
          $low_samples += 1
        end
      end
      $offset += $buff_size
    end
    $lows.push(reader.total_sample_frames) # Add end for final par
    puts reader.total_sample_frames
  end
  puts "Got " + ($lows.size - 1).to_s + " Positions with average length of " + $sum_lows.fdiv($count_lows).to_s + " and maximum length of " + $longest_low.to_s + " when using cut-off at " +ARGV[1] + " consecutive samples under average amplitude"
  
end
puts $lows.to_s
puts "Writing output in " + ($lows.size - 1).to_s + " parts"
$pieces = (0.upto $lows.size - 2).to_a
$new_pieces = $pieces.shuffle

Writer.new(ARGV[3], Format.new(:stereo, :pcm_16, 44100)) do |writer|
  $written = 0
  0.upto $new_pieces.size - 1 do |n|
    p = $new_pieces[n];
    puts "Part " + n.to_s + " from " + p.to_s + ":" + $lows[p].to_s + " to " + (p+1).to_s + ":" + $lows[p+1].to_s
    Reader.new(ARGV[0]) do |reader|
      # Skip part
      begin
        if $lows[p]> 0 then 
          $buff_size = $BUFF_CONST
          while ($buff_size > $lows[p]-1 - reader.current_sample_frame)
            reader.read($buff_size) 
          end 
          reader.read($lows[p]-1 - reader.current_sample_frame)
        end
#      rescue
#        puts "Read Rescue at " + p.to_s
      end
      begin
        $buff_size = $BUFF_CONST
        while ($buff_size >$lows[p+1] - reader.current_sample_frame)
          data = reader.read($buff_size)
          writer.write(data)
        end
        data = reader.read($lows[p+1] - reader.current_sample_frame)
        writer.write(data)
        $written += 1
#      rescue
        # Ignore
#        puts "Write Rescue at " + p.to_s
      end
    end
  end
end
puts "Wrote " + $written.to_s + " parts in new order"
