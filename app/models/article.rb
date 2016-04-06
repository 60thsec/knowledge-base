class Article < ActiveRecord::Base

  scope :without_soft_destroyed, -> { where(destroyed_at: nil) }

  def soft_destroy
    touch(:destroyed_at)
  end

  def restore
    update_attribute(:destroyed_at, nil)
  end

  def soft_destroyed?
    self.destroyed_at.present?
  end

  has_many :revisions, -> { order(:updated_at) }, dependent: :destroy
  belongs_to :current_revision, class_name: 'Revision', autosave: true
  before_destroy :unset_current_revision, prepend: true

  def unset_current_revision
    update_column(:current_revision_id, nil)
  end

  def autosaving(autosave)
    if current_revision.nil?
      self.current_revision = revisions.build(article: self, autosave: autosave)
    elsif current_revision.persisted?
      unless current_revision.autosave?
        self.current_revision = revisions.build(article: self)
      end
      current_revision.autosave = autosave
    end
    self
  end

  def title
    current_revision.try!(:title)
  end

  def title=(title)
    current_revision.title = title
  end

  def body
    current_revision.try!(:body)
  end

  def body=(body)
    current_revision.body = body
  end


  has_many :reviews, -> { order(:reviewed_at) }, dependent: :destroy

  # Should be called by review that needs reference to previous reviews in
  # sequence
  def update_prev_reviews(requesting_review)
    reviews.each_with_index do |review, i|
      review.update_prev_reviews(reviews[0...i])
      # there maybe multiple review objects for same record, make sure to
      # actually update the one that requested it
      if !requesting_review.equal?(review) &&
          requesting_review.id == review.id
        requesting_review.update_prev_reviews(reviews[0...i])
      end
    end
  end

  def last_reviewed_at
    reviews.last.try!(:reviewed_at)
  end

  def next_review_at
    reviews.last.try!(:next_at)
  end

  def next_review_at_for_sort
    next_review_at || Time.zone.at(0)
  end


  include ClassyEnum::ActiveRecord
  classy_enum_attr :format, default: :slim


  def body_html
    @body_html ||= format.render(body || '')
  end

  def body_doc
    @body_doc ||= Nokogiri::HTML.fragment(body_html)
  end

  def labels
    todo_count = body_doc.css('.todo').size
    todo_count > 0 ? ["TODO: #{todo_count}"] : []
  end

  def cards
    body_doc.css('[id|="card"]')
      .flat_map{ |d| Card.build_card_group(d, self) }
  end

end
