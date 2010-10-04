class SubnetsController < ApplicationController
  def index
    @search = Subnet.search params[:search]
    @subnets = @search.paginate(:page => params[:page])
  end

  def new
    @subnet = Subnet.new
  end

  def create
    @subnet = Subnet.new(params[:subnet])
    if @subnet.save
      flash[:foreman_notice] = "Successfully created subnet"
      redirect_to subnets_url
    else
      render :action => 'new'
    end
  end

  def edit
    @subnet = Subnet.find(params[:id])
  end

  def update
    @subnet = Subnet.find(params[:id])
    if @subnet.update_attributes(params[:subnet])
      flash[:foreman_notice] = "Successfully updated subnet"
      redirect_to subnets_url
    else
      render :action => 'edit'
    end
  end

  def destroy
    @subnet = Subnet.find(params[:id])
    @subnet.destroy
    flash[:foreman_notice] = "Successfully destroyed subnet"
    redirect_to subnets_url
  end
end
