# The card colour screen and the colour field on an issue.
module ExpertAgileColorsHelper
  # A swatch paints its whole box inline rather than taking it from the
  # stylesheet.
  #
  # Both screens that show the picker are outside the board, so nothing about
  # them guarantees the plugin's stylesheet is loaded — and a swatch that takes
  # its size from a class is a zero-sized empty span without one, which is how
  # the picker came to render as a row of bare radio buttons. The stylesheet
  # still arranges the swatches and marks the chosen one; it just no longer
  # decides whether they can be seen at all.
  def expert_agile_swatch_style(hex, size)
    box = "display: inline-block; box-sizing: border-box; width: #{size}px; height: #{size}px; " \
          "border: 1px solid #999; border-radius: 3px; vertical-align: middle; " \
          "text-align: center; line-height: #{size - 2}px;"
    hex.present? ? "#{box} background-color: #{hex};" : "#{box} background-color: #fff; color: #999;"
  end
end
