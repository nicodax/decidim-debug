# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Proposals
    describe NotifyProposalsMentionedJob do
      subject { described_class }

      include_context "when creating a comment"

      let(:comment) { create(:comment, commentable: commentable) }
      let(:proposal_component) { create(:proposal_component, organization: organization) }
      let(:proposal_metadata) { Decidim::ContentParsers::ProposalParser::Metadata.new([]) }
      let(:users) { [create(:user, :confirmed, organization: organization)] }
      let(:linked_proposal) { create(:proposal, component: proposal_component, users: users) }
      let(:linked_proposal_official) { create(:proposal, :official, component: proposal_component) }
      let(:author) { create(:user, organization: commentable.organization) }

      describe "integration" do
        it "is correctly scheduled" do
          ActiveJob::Base.queue_adapter = :test
          proposal_metadata[:linked_proposals] << linked_proposal
          proposal_metadata[:linked_proposals] << linked_proposal_official
          comment = create(:comment)

          expect do
            Decidim::Comments::CommentCreation.publish(comment, proposal: proposal_metadata)
          end.to have_enqueued_job.with(comment.id, proposal_metadata.linked_proposals)
        end
      end

      describe "with mentioned proposals" do
        let(:linked_proposals) do
          [
            linked_proposal.id,
            linked_proposal_official.id
          ]
        end

        let!(:space_admin) do
          create(:process_admin, participatory_process: linked_proposal_official.component.participatory_space)
        end

        it "notifies the author about it" do
          expect(Decidim::EventsManager)
            .to receive(:publish)
            .with(
              event: "decidim.events.proposals.proposal_mentioned",
              event_class: Decidim::Proposals::ProposalMentionedEvent,
              resource: commentable,
              affected_users: [linked_proposal.creator_author],
              extra: {
                comment_id: comment.id,
                mentioned_proposal_id: linked_proposal.id
              }
            )

          expect(Decidim::EventsManager)
            .to receive(:publish)
            .with(
              event: "decidim.events.proposals.proposal_mentioned",
              event_class: Decidim::Proposals::ProposalMentionedEvent,
              resource: commentable,
              affected_users: [space_admin],
              extra: {
                comment_id: comment.id,
                mentioned_proposal_id: linked_proposal_official.id
              }
            )

          subject.perform_now(comment.id, linked_proposals)
        end

        context "when the author is the same as proposal user" do
          before do
            comment.update(author: users.first)
          end

          it "does not notify the same user" do
            expect(Decidim::EventsManager)
              .not_to receive(:publish)
              .with(
                event: "decidim.events.proposals.proposal_mentioned",
                event_class: Decidim::Proposals::ProposalMentionedEvent,
                resource: commentable,
                affected_users: [linked_proposal.creator_author],
                extra: {
                  comment_id: comment.id,
                  mentioned_proposal_id: linked_proposal.id
                }
              )
            expect(Decidim::EventsManager)
              .to receive(:publish)
              .with(
                event: "decidim.events.proposals.proposal_mentioned",
                event_class: Decidim::Proposals::ProposalMentionedEvent,
                resource: commentable,
                affected_users: [space_admin],
                extra: {
                  comment_id: comment.id,
                  mentioned_proposal_id: linked_proposal_official.id
                }
              )

            subject.perform_now(comment.id, linked_proposals)
          end
        end
      end
    end
  end
end
