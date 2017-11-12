package Senf::Model::Comment;
use 5.026;

# ABSTRACT: Comment Model

use Moose;
use MooseX::Types::Path::Tiny qw/Dir/;
use Log::Any qw($log);

has 'store' => (
    is       => 'ro',
    isa      => 'Senf::Store',
    required => 1,
);

sub show_topic {
    my ( $self, $ident ) = @_;

    my $site  = $self->store->load_site($ident);
    my $topic = $self->store->load_topic($ident);

    if ( !$topic->show_comments || !$site->global_show_comments ) {
        Senf::X::Forbidden->throw(
            {   ident   => 'show-comments-disabled',
                message => 'Showing comments is disabled here',
            }
        );
    }

    my %data = map { $_ => $topic->$_ } qw(url);
    my @comments = $self->walk_comments($topic);
    $data{comments} = \@comments;

    return \%data;
}

sub walk_comments {
    my ( $self, $topic ) = @_;
    my @list;
    foreach my $comment ( $topic->all_comments ) {
        my %comment = map { $_ => $comment->$_ }
            qw (subject body created user_name user_email ident);
        if ( $comment->is_deleted ) {
            %comment = map { $_ => 'deleted' } keys %comment;
        }
        next unless $comment->status eq 'online';
        if ( $comment->comment_count ) {
            my @replies = $self->walk_comments($comment);
            $comment{comments} = \@replies;
        }
        push( @list, \%comment );
    }
    return @list;
}

sub create_comment {
    my ( $self, $topic_url, $comment_data ) = @_;

    my $site  = $self->store->load_site($topic_url);
    my $topic = $self->store->load_topic($topic_url);

    $comment_data->{ident} = $topic->comment_count;
    $self->_do_create( $site, $topic, $topic, $comment_data );
    $log->infof( "New comment create on %s", $topic->url );
}

sub create_reply {
    my ( $self, $topic_url, $reply_to_ident, $comment_data ) = @_;

    my $site     = $self->store->load_site($topic_url);
    my $topic    = $self->store->load_topic($topic_url);
    my $reply_to = $self->store->load_comment( $topic, $reply_to_ident );

    unless ( $reply_to->status eq 'online' ) {
        Senf::X::Forbidden->throw(
            {   ident   => 'cannot-reply-non-online-comment',
                message => "You cannot reply to a comment that's not online",
            }
        );
    }

    $comment_data->{ident} = $reply_to_ident . '.' . $reply_to->comment_count;
    $self->_do_create( $site, $topic, $reply_to, $comment_data );
}

sub _do_create {
    my ( $self, $site, $topic, $parent, $comment_data ) = @_;

    if ( !$topic->allow_comments || !$site->global_allow_comments ) {
        Senf::X::Forbidden->throw(
            {   ident   => 'create-comments-disabled',
                message => 'New comments are not accepted here',
            }
        );
    }

    if ( $topic->require_approval || $site->global_require_approval ) {
        $comment_data->{status} = 'pending';
    }
    else {
        $comment_data->{status} = 'online';
    }

    my $comment = Senf::Object::Comment->new( $comment_data->%* );

    push( $parent->comments->@*, $comment );
    $self->store->store_topic($topic);
}

__PACKAGE__->meta->make_immutable;

